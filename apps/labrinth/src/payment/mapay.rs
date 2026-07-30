use std::collections::HashMap;

use hmac::{Hmac, Mac};
use reqwest::Client;
use sha2::Sha256;

use super::{
    CreateOrderRequest, CreateOrderResponse, OrderStatus, PaymentError, PaymentGateway,
    PaymentNotification, PaymentStatus,
};

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone)]
pub struct MapayGateway {
    pub api_url: String,
    pub app_id: String,
    pub app_secret: String,
    pub notify_url: String,
    pub return_url: String,
    pub http_client: Client,
}

impl MapayGateway {
    pub fn new(
        api_url: impl Into<String>,
        app_id: impl Into<String>,
        app_secret: impl Into<String>,
        notify_url: impl Into<String>,
        return_url: impl Into<String>,
    ) -> Self {
        Self {
            api_url: api_url.into(),
            app_id: app_id.into(),
            app_secret: app_secret.into(),
            notify_url: notify_url.into(),
            return_url: return_url.into(),
            http_client: Client::new(),
        }
    }

    fn sign(&self, payload: &str) -> String {
        let mut mac =
            HmacSha256::new_from_slice(self.app_secret.as_bytes()).expect("HMAC key length");
        mac.update(payload.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }

    fn sign_params(&self, params: &HashMap<String, String>) -> String {
        let mut keys: Vec<&String> = params.keys().collect();
        keys.sort();

        let mut sign_str = String::new();
        for (i, key) in keys.iter().enumerate() {
            let value = &params[*key];
            if i > 0 {
                sign_str.push('&');
            }
            sign_str.push_str(key);
            sign_str.push('=');
            sign_str.push_str(value);
        }

        self.sign(&sign_str)
    }

    fn amount_to_yuan(amount: i64) -> String {
        format!("{:.2}", amount as f64 / 100.0)
    }

    fn yuan_to_amount(yuan: &str) -> i64 {
        (yuan.parse::<f64>().unwrap_or(0.0) * 100.0).round() as i64
    }
}

#[async_trait::async_trait]
impl PaymentGateway for MapayGateway {
    async fn create_order(
        &self,
        order: CreateOrderRequest,
    ) -> Result<CreateOrderResponse, PaymentError> {
        let mut params = HashMap::new();
        params.insert("app_id".to_string(), self.app_id.clone());
        params.insert("out_trade_no".to_string(), order.order_id);
        params.insert("amount".to_string(), Self::amount_to_yuan(order.amount));
        params.insert("notify_url".to_string(), self.notify_url.clone());
        params.insert("return_url".to_string(), self.return_url.clone());
        params.insert("subject".to_string(), order.subject);
        params.insert("description".to_string(), order.description);
        params.insert("client_ip".to_string(), order.client_ip);

        let sign = self.sign_params(&params);
        params.insert("sign".to_string(), sign);

        let url = format!("{}/api/gateway", self.api_url.trim_end_matches('/'));

        let resp = self
            .http_client
            .post(&url)
            .json(&params)
            .send()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let code = json["code"].as_i64().unwrap_or(-1);
        if code != 0 {
            let msg = json["msg"]
                .as_str()
                .unwrap_or("mapay create_order failed")
                .to_string();
            return Err(PaymentError::Internal(msg));
        }

        let data = &json["data"];
        let qr_code = data["qr_code"].as_str().map(String::from);
        let trade_no = data["trade_no"].as_str().map(String::from);

        Ok(CreateOrderResponse {
            payment_url: data["payment_url"].as_str().map(String::from),
            qr_code,
            trade_no,
            raw: json,
        })
    }

    async fn verify_notification(
        &self,
        body: &str,
        _headers: &[(String, String)],
    ) -> Result<PaymentNotification, PaymentError> {
        let json: serde_json::Value =
            serde_json::from_str(body).map_err(|_| PaymentError::InvalidSignature)?;

        let received_sign = json["sign"]
            .as_str()
            .ok_or(PaymentError::InvalidSignature)?
            .to_string();

        let mut params = HashMap::new();
        if let Some(obj) = json.as_object() {
            for (key, value) in obj {
                if key != "sign" {
                    let str_val = match value {
                        serde_json::Value::String(s) => s.clone(),
                        other => other.to_string(),
                    };
                    params.insert(key.clone(), str_val);
                }
            }
        }

        let expected_sign = self.sign_params(&params);
        if expected_sign != received_sign {
            return Err(PaymentError::InvalidSignature);
        }

        let order_id = params
            .get("out_trade_no")
            .ok_or(PaymentError::InvalidSignature)?
            .clone();
        let trade_no = params
            .get("trade_no")
            .ok_or(PaymentError::InvalidSignature)?
            .clone();
        let amount_str = params.get("amount").ok_or(PaymentError::InvalidSignature)?;
        let amount = Self::yuan_to_amount(amount_str);

        let status_str = params.get("status").map(|s| s.as_str()).unwrap_or("");
        let status = match status_str {
            "1" | "success" => PaymentStatus::Paid,
            "0" | "pending" => PaymentStatus::Pending,
            "2" | "refund" => PaymentStatus::Refunded,
            _ => PaymentStatus::Failed,
        };

        Ok(PaymentNotification {
            order_id,
            trade_no,
            amount,
            currency: "CNY".to_string(),
            status,
            paid_at: None,
            raw: json,
        })
    }

    async fn query_order(&self, order_id: &str) -> Result<OrderStatus, PaymentError> {
        let mut params = HashMap::new();
        params.insert("app_id".to_string(), self.app_id.clone());
        params.insert("out_trade_no".to_string(), order_id.to_string());

        let sign = self.sign_params(&params);
        params.insert("sign".to_string(), sign);

        let url = format!("{}/api/order/query", self.api_url.trim_end_matches('/'));

        let resp = self
            .http_client
            .post(&url)
            .json(&params)
            .send()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let code = json["code"].as_i64().unwrap_or(-1);
        if code != 0 {
            return Err(PaymentError::OrderNotFound(order_id.to_string()));
        }

        let data = &json["data"];
        let status_str = data["status"].as_str().unwrap_or("");
        let status = match status_str {
            "1" | "success" => PaymentStatus::Paid,
            "0" | "pending" => PaymentStatus::Pending,
            "2" | "refund" => PaymentStatus::Refunded,
            _ => PaymentStatus::Failed,
        };

        let amount = data["amount"]
            .as_str()
            .map(|a| Self::yuan_to_amount(a));

        Ok(OrderStatus {
            status,
            trade_no: data["trade_no"].as_str().map(String::from),
            amount,
            paid_at: None,
        })
    }

    async fn refund(
        &self,
        order_id: &str,
        amount: Option<i64>,
    ) -> Result<(), PaymentError> {
        let mut params = HashMap::new();
        params.insert("app_id".to_string(), self.app_id.clone());
        params.insert("out_trade_no".to_string(), order_id.to_string());
        if let Some(amt) = amount {
            params.insert("amount".to_string(), Self::amount_to_yuan(amt));
        }

        let sign = self.sign_params(&params);
        params.insert("sign".to_string(), sign);

        let url = format!("{}/api/order/refund", self.api_url.trim_end_matches('/'));

        let resp = self
            .http_client
            .post(&url)
            .json(&params)
            .send()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let code = json["code"].as_i64().unwrap_or(-1);
        if code != 0 {
            let msg = json["msg"]
                .as_str()
                .unwrap_or("refund failed")
                .to_string();
            return Err(PaymentError::RefundFailed(msg));
        }

        Ok(())
    }

    fn name(&self) -> &'static str {
        "mapay"
    }
}
