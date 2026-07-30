use std::collections::HashMap;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

pub mod alipay;
pub mod epay;
pub mod codepay;
pub mod wechatpay;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateOrderRequest {
    pub order_id: String,
    pub amount: i64,
    pub currency: String,
    pub subject: String,
    pub description: String,
    pub notify_url: String,
    pub return_url: String,
    pub client_ip: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateOrderResponse {
    pub payment_url: Option<String>,
    pub qr_code: Option<String>,
    pub trade_no: Option<String>,
    pub raw: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaymentNotification {
    pub order_id: String,
    pub trade_no: String,
    pub amount: i64,
    pub currency: String,
    pub status: PaymentStatus,
    pub paid_at: Option<DateTime<Utc>>,
    pub raw: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderStatus {
    pub status: PaymentStatus,
    pub trade_no: Option<String>,
    pub amount: Option<i64>,
    pub paid_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PaymentStatus {
    Pending,
    Paid,
    Failed,
    Refunded,
}

#[derive(Error, Debug)]
pub enum PaymentError {
    #[error("network error: {0}")]
    Network(String),
    #[error("invalid signature")]
    InvalidSignature,
    #[error("order not found: {0}")]
    OrderNotFound(String),
    #[error("refund failed: {0}")]
    RefundFailed(String),
    #[error("internal error: {0}")]
    Internal(String),
}

#[async_trait]
pub trait PaymentGateway: Send + Sync {
    async fn create_order(
        &self,
        order: CreateOrderRequest,
    ) -> Result<CreateOrderResponse, PaymentError>;

    async fn verify_notification(
        &self,
        body: &str,
        headers: &[(String, String)],
    ) -> Result<PaymentNotification, PaymentError>;

    async fn query_order(&self, order_id: &str) -> Result<OrderStatus, PaymentError>;

    async fn refund(
        &self,
        order_id: &str,
        amount: Option<i64>,
    ) -> Result<(), PaymentError>;

    fn name(&self) -> &'static str;
}

pub struct PaymentGatewayRegistry {
    gateways: HashMap<String, Box<dyn PaymentGateway + Send + Sync>>,
}

impl PaymentGatewayRegistry {
    pub fn new() -> Self {
        Self {
            gateways: HashMap::new(),
        }
    }

    pub fn register(&mut self, gateway: Box<dyn PaymentGateway + Send + Sync>) {
        self.gateways.insert(gateway.name().to_string(), gateway);
    }

    pub fn get(&self, name: &str) -> Option<&(dyn PaymentGateway + Send + Sync)> {
        self.gateways.get(name).map(|g| g.as_ref())
    }

    pub fn names(&self) -> Vec<&str> {
        self.gateways.keys().map(|k| k.as_str()).collect()
    }
}

impl Default for PaymentGatewayRegistry {
    fn default() -> Self {
        Self::new()
    }
}
