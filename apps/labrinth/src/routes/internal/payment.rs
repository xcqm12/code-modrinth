use actix_web::{HttpResponse, web};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::payment::{CreateOrderRequest, PaymentGatewayRegistry};
use crate::routes::ApiError;

pub fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/payment")
            .service(create_order)
            .service(payment_notify)
            .service(query_order)
            .service(refund_order)
            .service(list_gateways),
    );
}

#[derive(Deserialize)]
struct CreateOrderQuery {
    gateway: String,
    order_id: String,
    amount: i64,
    currency: Option<String>,
    subject: Option<String>,
    description: Option<String>,
    return_url: Option<String>,
    client_ip: Option<String>,
}

#[derive(Serialize)]
struct CreateOrderResponseBody {
    payment_url: Option<String>,
    qr_code: Option<String>,
    trade_no: Option<String>,
}

#[actix_web::post("/create")]
pub async fn create_order(
    registry: web::Data<PaymentGatewayRegistry>,
    query: web::Query<CreateOrderQuery>,
) -> Result<HttpResponse, ApiError> {
    let gateway_name = &query.gateway;
    let gateway = registry
        .get(gateway_name)
        .ok_or_else(|| ApiError::Request(eyre::eyre!("unknown payment gateway: {gateway_name}")))?;

    let request = CreateOrderRequest {
        order_id: query.order_id.clone(),
        amount: query.amount,
        currency: query.currency.clone().unwrap_or_else(|| "CNY".into()),
        subject: query.subject.clone().unwrap_or_default(),
        description: query.description.clone().unwrap_or_default(),
        notify_url: format!("/_internal/payment/notify/{}", gateway_name),
        return_url: query.return_url.clone().unwrap_or_default(),
        client_ip: query.client_ip.clone().unwrap_or_else(|| "127.0.0.1".into()),
    };

    let response = gateway.create_order(request).await.map_err(|e| {
        ApiError::Internal(eyre::eyre!("payment create_order failed: {e}"))
    })?;

    Ok(HttpResponse::Ok().json(CreateOrderResponseBody {
        payment_url: response.payment_url,
        qr_code: response.qr_code,
        trade_no: response.trade_no,
    }))
}

#[actix_web::post("/notify/{gateway}")]
pub async fn payment_notify(
    registry: web::Data<PaymentGatewayRegistry>,
    path: web::Path<String>,
    body: String,
    req: actix_web::HttpRequest,
) -> Result<HttpResponse, ApiError> {
    let gateway_name = path.into_inner();
    let gateway = registry.get(&gateway_name).ok_or_else(|| {
        ApiError::Request(eyre::eyre!("unknown payment gateway: {gateway_name}"))
    })?;

    let headers: Vec<(String, String)> = req
        .headers()
        .iter()
        .map(|(k, v)| {
            (
                k.as_str().to_string(),
                v.to_str().unwrap_or_default().to_string(),
            )
        })
        .collect();

    let notification = gateway
        .verify_notification(&body, &headers)
        .await
        .map_err(|e| {
            ApiError::Internal(eyre::eyre!(
                "payment notification verification failed: {e}"
            ))
        })?;

    match notification.status {
        crate::payment::PaymentStatus::Paid => {
            // TODO: update charge status in database, provision services
            tracing::info!(
                "Payment received: order={}, trade_no={}, amount={}",
                notification.order_id,
                notification.trade_no,
                notification.amount
            );
        }
        _ => {
            tracing::warn!(
                "Payment notification non-success: order={}, status={:?}",
                notification.order_id,
                notification.status
            );
        }
    }

    Ok(HttpResponse::Ok().json(json!({"status": "ok"})))
}

#[derive(Deserialize)]
struct QueryOrderQuery {
    gateway: String,
    order_id: String,
}

#[actix_web::get("/query")]
pub async fn query_order(
    registry: web::Data<PaymentGatewayRegistry>,
    query: web::Query<QueryOrderQuery>,
) -> Result<HttpResponse, ApiError> {
    let gateway = registry.get(&query.gateway).ok_or_else(|| {
        ApiError::Request(eyre::eyre!("unknown payment gateway: {}", query.gateway))
    })?;

    let status = gateway.query_order(&query.order_id).await.map_err(|e| {
        ApiError::Internal(eyre::eyre!("payment query failed: {e}"))
    })?;

    Ok(HttpResponse::Ok().json(&status))
}

#[derive(Deserialize)]
struct RefundOrderQuery {
    gateway: String,
    order_id: String,
    amount: Option<i64>,
}

#[actix_web::post("/refund")]
pub async fn refund_order(
    registry: web::Data<PaymentGatewayRegistry>,
    query: web::Query<RefundOrderQuery>,
) -> Result<HttpResponse, ApiError> {
    let gateway = registry.get(&query.gateway).ok_or_else(|| {
        ApiError::Request(eyre::eyre!("unknown payment gateway: {}", query.gateway))
    })?;

    gateway
        .refund(&query.order_id, query.amount)
        .await
        .map_err(|e| ApiError::Internal(eyre::eyre!("payment refund failed: {e}")))?;

    Ok(HttpResponse::Ok().json(json!({"status": "ok"})))
}

#[actix_web::get("/gateways")]
pub async fn list_gateways(
    registry: web::Data<PaymentGatewayRegistry>,
) -> HttpResponse {
    let names = registry.names();
    HttpResponse::Ok().json(names)
}
