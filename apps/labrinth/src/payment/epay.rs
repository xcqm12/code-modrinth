use std::collections::HashMap;

use md5::{Digest, Md5};
use reqwest::Client;
use urlencoding::encode;

use super::{
    CreateOrderRequest, CreateOrderResponse, OrderStatus, PaymentError, PaymentGateway,
    PaymentNotification, PaymentStatus,
};

#[derive(Debug, Clone)]
pub struct EpayGateway {
    pub api_url: String,
    pub pid: String,
    pub key: String,
    pub notify_url: String,
    pub return_url: String,
    pub http_client: Client,
}

impl EpayGateway {
    pub fn new(
        api_url: impl Into<String>,
        pid: impl Into<String>,
        key: impl Into<String>,
        notify_url: impl Into<String>,
        return_url: impl Into<String>,
    ) -> Self {
        Self {
            api_url: api_url.into(),
            pid: pid.into(),
            key: key.into(),
            notify_url: notify_url.into(),
            return_url: return_url.into(),
            http_client: Client::new(),
        }
    }

    fn sign(&self, params: &HashMap<String, String>) -> String {
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
        sign_str.push_str("&key=");
        sign_str.push_str(&self.key);

        hex::encode(Md5::digest(sign_str.as_bytes()))
    }

    fn parse_form_body(body: &str) -> HashMap<String, String> {
        let mut params = HashMap::new();
        for pair in body.split('&') {
            let mut parts = pair.splitn(2, '=');
            let key = parts.next().unwrap_or_default().to_string();
            let value = urlencoding::decode(parts.next().unwrap_or_default())
                .unwrap_or_default()
                .into_owned();
            if !key.is_empty() {
                params.insert(key, value);
            }
        }
        params
    }

    fn verify_sign(&self, params: &HashMap<String, String>) -> bool {
        let sign = match params.get("sign") {
            Some(s) => s,
            None => return false,
        };

        let mut verify_params = params.clone();
        verify_params.remove("sign");
        verify_params.remove("sign_type");

        let expected = self.sign(&verify_params);
        expected == *sign
    }

    fn amount_to_yuan(amount: i64) -> String {
        format!("{:.2}", amount as f64 / 100.0)
    }

    fn yuan_to_amount(yuan: &str) -> i64 {
        (yuan.parse::<f64>().unwrap_or(0.0) * 100.0).round() as i64
    }
}

#[async_trait::async_trait]
impl PaymentGateway for EpayGateway {
    async fn create_order(
        &self,
        order: CreateOrderRequest,
    ) -> Result<CreateOrderResponse, PaymentError> {
        let mut params = HashMap::new();
        params.insert("pid".to_string(), self.pid.clone());
        params.insert("type".to_string(), "alipay".to_string());
        params.insert("out_trade_no".to_string(), order.order_id);
        params.insert("notify_url".to_string(), self.notify_url.clone());
        params.insert("return_url".to_string(), self.return_url.clone());
        params.insert("name".to_string(), order.subject);
        params.insert("money".to_string(), Self::amount_to_yuan(order.amount));

        let sign = self.sign(&params);
        params.insert("sign".to_string(), sign);
        params.insert("sign_type".to_string(), "MD5".to_string());

        let base = self.api_url.trim_end_matches('/').to_string();
        let query: String = params
            .iter()
            .map(|(k, v)| format!("{}={}", k, encode(v)))
            .collect::<Vec<_>>()
            .join("&");
        let payment_url = format!("{}/submit.php?{}", base, query);

        Ok(CreateOrderResponse {
            payment_url: Some(payment_url),
            qr_code: None,
            trade_no: None,
            raw: serde_json::Value::Null,
        })
    }

    async fn verify_notification(
        &self,
        body: &str,
        _headers: &[(String, String)],
    ) -> Result<PaymentNotification, PaymentError> {
        let params = Self::parse_form_body(body);

        if !self.verify_sign(&params) {
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
        let money = params.get("money").ok_or(PaymentError::InvalidSignature)?;
        let amount = Self::yuan_to_amount(money);
        let trade_status = params.get("trade_status").map(|s| s.as_str()).unwrap_or("");

        let status = match trade_status {
            "TRADE_SUCCESS" | "TRADE_FINISHED" => PaymentStatus::Paid,
            "TRADE_CLOSED" => PaymentStatus::Failed,
            "REFUND_SUCCESS" => PaymentStatus::Refunded,
            "WAIT_BUYER_PAY" | "TRADE_PENDING" => PaymentStatus::Pending,
            _ => PaymentStatus::Failed,
        };

        let raw = serde_json::to_value(&params).unwrap_or(serde_json::Value::Null);

        Ok(PaymentNotification {
            order_id,
            trade_no,
            amount,
            currency: "CNY".to_string(),
            status,
            paid_at: None,
            raw,
        })
    }

    async fn query_order(&self, order_id: &str) -> Result<OrderStatus, PaymentError> {
        let mut params = HashMap::new();
        params.insert("act".to_string(), "order".to_string());
        params.insert("pid".to_string(), self.pid.clone());
        params.insert("out_trade_no".to_string(), order_id.to_string());

        let sign = self.sign(&params);
        params.insert("sign".to_string(), sign);
        params.insert("sign_type".to_string(), "MD5".to_string());

        let base = self.api_url.trim_end_matches('/').to_string();
        let query: String = params
            .iter()
            .map(|(k, v)| format!("{}={}", k, encode(v)))
            .collect::<Vec<_>>()
            .join("&");
        let url = format!("{}/api.php?{}", base, query);

        let resp = self
            .http_client
            .get(&url)
            .send()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let text = resp
            .text()
            .await
            .map_err(|e| PaymentError::Network(e.to_string()))?;

        let json: serde_json::Value =
            serde_json::from_str(&text).map_err(|e| PaymentError::Network(e.to_string()))?;

        let status = match json["status"].as_str() {
            Some("1") => PaymentStatus::Paid,
            Some("0") => PaymentStatus::Pending,
            _ => PaymentStatus::Failed,
        };

        let amount = json["money"]
            .as_str()
            .map(|m| Self::yuan_to_amount(m));

        Ok(OrderStatus {
            status,
            trade_no: json["trade_no"].as_str().map(String::from),
            amount,
            paid_at: None,
        })
    }

    async fn refund(
        &self,
        _order_id: &str,
        _amount: Option<i64>,
    ) -> Result<(), PaymentError> {
        Err(PaymentError::RefundFailed(
            "epay does not support automated refunds".to_string(),
        ))
    }

    fn name(&self) -> &'static str {
        "epay"
    }
}
