use async_trait::async_trait;
use chrono::{DateTime, TimeZone, Utc};
use hmac::{Hmac, Mac};
use rand::Rng;
use reqwest::Client;
use sha2::Sha256;
use std::time::{SystemTime, UNIX_EPOCH};

use super::{
    CreateOrderRequest, CreateOrderResponse, OrderStatus, PaymentError, PaymentGateway,
    PaymentNotification, PaymentStatus,
};

type HmacSha256 = Hmac<Sha256>;

/// Configuration for the WeChat Pay (微信支付) payment gateway.
#[derive(Clone)]
pub struct WechatPayConfig {
    /// 应用ID (AppID) - the WeChat application identifier issued by WeChat.
    pub app_id: String,
    /// 商户号 (Merchant ID) - the merchant's WeChat Pay account ID (mchid).
    pub mch_id: String,
    /// API密钥 (API Key) - used for HMAC-SHA256 signing of notifications and requests.
    pub api_key: String,
    /// API v3密钥 (API v3 Key) - used for decrypting sensitive response fields in V3 API.
    pub api_v3_key: String,
    /// Path to the merchant certificate file (apiclient_key.pem).
    /// Required for V3 API authentication (RSA2048 signing of the Authorization header).
    pub cert_path: Option<String>,
    /// Gateway base URL, defaults to "https://api.mch.weixin.qq.com".
    pub gateway_url: String,
    /// Notification URL for payment callbacks (异步通知URL).
    pub notify_url: String,
}

/// WeChat Pay (微信支付) payment gateway implementation.
///
/// This gateway implements the WeChat Pay V3 API (JSON-based) for payment operations,
/// with HMAC-SHA256 based signing for notification verification.
///
/// # WeChat Pay API Flow (Native Pay / 扫码支付):
///
/// 1. **Create Order**: The backend calls the V3 Native Pay API
///    (`POST /v3/pay/transactions/native`) to obtain a `code_url`.
///    The `code_url` is a short URL that encodes the order information.
///
/// 2. **Display QR Code**: The backend returns the `code_url` as `qr_code`
///    to the frontend, which renders it as a QR code image.
///
/// 3. **User Scans & Pays**: The user scans the QR code using the WeChat app,
///    reviews the order, and confirms payment via fingerprint/password.
///
/// 4. **Notification**: WeChat Pay sends a POST request to the `notify_url`
///    when the payment succeeds. The backend must verify the HMAC-SHA256
///    signature before updating the order status.
///
/// 5. **Order Query** (fallback): If the notification is not received,
///    the backend can proactively query the order status using
///    `GET /v3/pay/transactions/out-trade-no/{out_trade_no}`.
///
/// # Amount Convention:
///
/// All monetary amounts are in 分 (fēn, cents). For example:
/// - 1 CNY (元) = 100 cents (分)
/// - An order of ¥12.50 should be passed as `amount: 1250`
///
/// # Signature Scheme:
///
/// HMAC-SHA256 is used for:
/// - Notification verification (signing of the notification body + headers)
/// - Request signing for certain API operations
///
/// The HMAC key is the `api_key` configured for the merchant account.
///
/// # V3 API Authentication:
///
/// The standard WeChat Pay V3 API uses RSA-SHA256 signing with the
/// merchant's certificate for the `Authorization` header
/// (`WECHATPAY2-SHA256-RSA2048` scheme). This implementation uses
/// a simplified HMAC-SHA256 based auth token for the `Authorization`
/// header, which is suitable for development/testing. For production
/// use, replace `generate_auth_token` with proper RSA signing using
/// the merchant private key loaded from `cert_path`.
#[derive(Clone)]
pub struct WechatPayGateway {
    config: WechatPayConfig,
    http_client: Client,
}

impl WechatPayGateway {
    /// Creates a new WeChat Pay gateway instance with the given configuration.
    pub fn new(config: WechatPayConfig) -> Self {
        Self {
            http_client: Client::new(),
            config,
        }
    }

    /// Returns the base URL for the WeChat Pay API.
    fn base_url(&self) -> &str {
        &self.config.gateway_url
    }

    /// Generates a cryptographically random nonce string (32 alphanumeric characters).
    fn generate_nonce(&self) -> String {
        rand::thread_rng()
            .sample_iter(&rand::distributions::Alphanumeric)
            .take(32)
            .map(char::from)
            .collect()
    }

    /// Returns the current Unix timestamp as a string.
    fn current_timestamp(&self) -> String {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .to_string()
    }

    /// Generates an HMAC-SHA256 based authorization token for V3 API calls.
    ///
    /// The canonical request string used for signing is:
    /// ```text
    /// {HTTP_METHOD}\n{URL_PATH_AND_QUERY}\n{TIMESTAMP}\n{NONCE}\n{REQUEST_BODY}\n
    /// ```
    ///
    /// This is then signed with HMAC-SHA256 using the `api_key`.
    ///
    /// Note: The official WeChat Pay V3 API uses RSA-SHA256 with the merchant
    /// certificate private key (`WECHATPAY2-SHA256-RSA2048`). This HMAC-based
    /// token is a simplified alternative. Replace with RSA signing for production.
    fn generate_auth_token(&self, method: &str, path: &str, body: &str) -> String {
        let timestamp = self.current_timestamp();
        let nonce = self.generate_nonce();
        let message = format!("{method}\n{path}\n{timestamp}\n{nonce}\n{body}\n");

        let mut mac = HmacSha256::new_from_slice(self.config.api_key.as_bytes())
            .expect("HMAC key should be valid");
        mac.update(message.as_bytes());
        let signature = hex::encode(mac.finalize().into_bytes());

        format!(
            "WECHATPAY2-HMAC-SHA256 mchid=\"{}\",nonce_str=\"{}\",timestamp=\"{}\",signature=\"{}\"",
            self.config.mch_id, nonce, timestamp, signature
        )
    }

    /// Computes an HMAC-SHA256 signature for a given string payload.
    ///
    /// Used for notification verification and general-purpose signing.
    fn sign_hmac_sha256(&self, data: &str) -> String {
        let mut mac = HmacSha256::new_from_slice(self.config.api_key.as_bytes())
            .expect("HMAC key should be valid");
        mac.update(data.as_bytes());
        hex::encode(mac.finalize().into_bytes()).to_uppercase()
    }

    /// Parses a WeChat Pay V3 timestamp string into `DateTime<Utc>`.
    ///
    /// WeChat Pay uses the format `yyyy-MM-DDTHH:mm:ss+08:00` (Beijing time)
    /// or `yyyy-MM-DDTHH:mm:ssZ` (UTC).
    fn parse_wechat_datetime(&self, s: &str) -> Option<DateTime<Utc>> {
        // Try parsing with timezone offset first (e.g. "2024-01-15T10:30:00+08:00")
        if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
            return Some(dt.with_timezone(&Utc));
        }
        // Try RFC3339 without timezone (assume UTC)
        if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S") {
            return Some(Utc.from_utc_datetime(&dt));
        }
        None
    }
}

#[async_trait]
impl PaymentGateway for WechatPayGateway {
    fn name(&self) -> &'static str {
        "wechatpay"
    }

    /// Creates a WeChat Pay order using the V3 Native Pay API.
    ///
    /// # API Endpoint
    /// `POST https://api.mch.weixin.qq.com/v3/pay/transactions/native`
    ///
    /// # Request Body (JSON)
    /// ```json
    /// {
    ///   "appid": "wx_app_id",
    ///   "mchid": "merchant_id",
    ///   "description": "Order description",
    ///   "out_trade_no": "merchant_order_id",
    ///   "notify_url": "https://example.com/notify",
    ///   "amount": {
    ///     "total": 100,
    ///     "currency": "CNY"
    ///   },
    ///   "scene_info": {
    ///     "payer_client_ip": "123.123.123.123"
    ///   }
    /// }
    /// ```
    ///
    /// # Response
    /// Returns a `code_url` which is a short URL that can be rendered as a QR code.
    /// The user scans this QR code in the WeChat app to complete the payment.
    async fn create_order(
        &self,
        order: CreateOrderRequest,
    ) -> Result<CreateOrderResponse, PaymentError> {
        let path = "/v3/pay/transactions/native";
        let url = format!("{}{}", self.base_url(), path);

        // WeChat Pay amounts are in 分 (cents). The incoming amount is already in cents.
        let total = order.amount;

        let body = serde_json::json!({
            "appid": self.config.app_id,
            "mchid": self.config.mch_id,
            "description": order.subject,
            "out_trade_no": order.order_id,
            "notify_url": order.notify_url,
            "amount": {
                "total": total,
                "currency": "CNY"
            },
            "scene_info": {
                "payer_client_ip": order.client_ip
            }
        });

        let body_str = body.to_string();
        let auth_token = self.generate_auth_token("POST", path, &body_str);

        let response = self
            .http_client
            .post(&url)
            .header("Authorization", &auth_token)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("User-Agent", "labrinth-wechatpay")
            .body(body_str)
            .send()
            .await
            .map_err(|e| PaymentError::Network(format!("failed to send create_order request: {e}")))?;

        let status = response.status();
        let response_text = response
            .text()
            .await
            .map_err(|e| PaymentError::Network(format!("failed to read create_order response body: {e}")))?;

        if !status.is_success() {
            return Err(PaymentError::Network(format!(
                "wechatpay create_order failed with status {status}: {response_text}"
            )));
        }

        let response_json: serde_json::Value = serde_json::from_str(&response_text)
            .map_err(|e| PaymentError::Internal(format!("failed to parse create_order response: {e}")))?;

        // Extract the code_url from the response
        // Response format: { "code_url": "weixin://pay/...", "prepay_id": "wx..." }
        let code_url = response_json
            .get("code_url")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let prepay_id = response_json
            .get("prepay_id")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        Ok(CreateOrderResponse {
            payment_url: prepay_id.clone(),
            qr_code: code_url,
            trade_no: prepay_id,
            raw: response_json,
        })
    }

    /// Verifies a WeChat Pay payment notification using HMAC-SHA256.
    ///
    /// # Notification Verification Flow
    ///
    /// WeChat Pay sends a POST request to the configured `notify_url` with:
    /// - **Headers**: `Wechatpay-Signature`, `Wechatpay-Nonce`, `Wechatpay-Timestamp`,
    ///   `Wechatpay-Serial`
    /// - **Body** (JSON, V3 format):
    ///   ```json
    ///   {
    ///     "id": "EV-2018022511223320873",
    ///     "create_time": "2024-01-15T10:30:00+08:00",
    ///     "event_type": "TRANSACTION.SUCCESS",
    ///     "resource_type": "encrypt-resource",
    ///     "resource": {
    ///       "algorithm": "AEAD_AES_256_GCM",
    ///       "ciphertext": "...",
    ///       "nonce": "...",
    ///       "associated_data": ""
    ///     }
    ///   }
    ///   ```
    ///
    /// **Signature verification (HMAC-SHA256):**
    ///
    /// The canonical signing string is constructed from the `Wechatpay-Timestamp`,
    /// `Wechatpay-Nonce`, and the request body:
    ///
    /// ```text
    /// {timestamp}\n{nonce}\n{body}\n
    /// ```
    ///
    /// This string is signed with HMAC-SHA256 using the configured `api_key`.
    /// The resulting hex digest is compared (case-insensitive) to the value
    /// of the `Wechatpay-Signature` header.
    ///
    /// For a production system, the official V3 notification verification
    /// requires decrypting the `resource.ciphertext` with the `api_v3_key`
    /// using AEAD_AES_256_GCM, then parsing the decrypted JSON for the
    /// actual payment details. This implementation performs the HMAC-SHA256
    /// signature verification of the notification envelope, and then extracts
    /// the order information from the notification body fields.
    async fn verify_notification(
        &self,
        body: &str,
        headers: &[(String, String)],
    ) -> Result<PaymentNotification, PaymentError> {
        // Extract WeChat Pay headers (case-insensitive lookup)
        let header_map: std::collections::HashMap<String, String> = headers
            .iter()
            .map(|(k, v)| (k.to_lowercase(), v.clone()))
            .collect();

        let signature = header_map
            .get("wechatpay-signature")
            .ok_or(PaymentError::InvalidSignature)?;

        let timestamp = header_map
            .get("wechatpay-timestamp")
            .ok_or(PaymentError::InvalidSignature)?;

        let nonce = header_map
            .get("wechatpay-nonce")
            .ok_or(PaymentError::InvalidSignature)?;

        // Build the canonical signing string: timestamp\nnonce\nbody\n
        let signing_string = format!("{timestamp}\n{nonce}\n{body}\n");

        // Compute HMAC-SHA256 of the signing string
        let computed_sig = self.sign_hmac_sha256(&signing_string);

        // Verify the signature (case-insensitive comparison)
        if computed_sig.to_lowercase() != signature.to_lowercase() {
            return Err(PaymentError::InvalidSignature);
        }

        // Parse the notification JSON body
        let notification_json: serde_json::Value = serde_json::from_str(body)
            .map_err(|e| PaymentError::Internal(format!("failed to parse notification body: {e}")))?;

        // Extract order information from the notification
        // For V3 notifications, the actual payment data is in:
        //   resource.ciphertext (AEAD_AES_256_GCM encrypted)
        // The resource summary fields are in:
        //   resource.algorithm, resource.ciphertext, resource.nonce, resource.associated_data
        //
        // For V2-style JSON notifications (or simplified V3 with plaintext),
        // the data may also appear at the top level:
        //   out_trade_no, transaction_id, trade_type, trade_state, success_time, amount

        // Try extracting from the resource summary fields if present (V3 encrypted format),
        // or from top-level fields (simplified/legacy format)
        let resource = notification_json.get("resource");

        // Attempt to extract order_id from the notification
        // Standard WeChat Pay V3 notifications include out_trade_no in the encrypted
        // resource, but some implementations also mirror it at the top level
        let order_id = notification_json
            .get("out_trade_no")
            .and_then(|v| v.as_str())
            .or_else(|| {
                // Fall back to the notification ID as a reference
                notification_json
                    .get("id")
                    .and_then(|v| v.as_str())
            })
            .unwrap_or("unknown")
            .to_string();

        // Extract trade_no (WeChat Pay transaction ID)
        let trade_no = notification_json
            .get("transaction_id")
            .and_then(|v| v.as_str())
            .or_else(|| {
                resource
                    .and_then(|r| r.get("transaction_id"))
                    .and_then(|v| v.as_str())
            })
            .unwrap_or("")
            .to_string();

        // Extract the payment amount (in cents)
        let amount = notification_json
            .get("amount")
            .and_then(|a| a.get("total"))
            .and_then(|v| v.as_i64())
            .or_else(|| {
                resource
                    .and_then(|r| r.get("amount"))
                    .and_then(|a| a.get("total"))
                    .and_then(|v| v.as_i64())
            })
            .unwrap_or(0);

        // Determine payment status from the event type or trade state
        let event_type = notification_json
            .get("event_type")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let trade_state = notification_json
            .get("trade_state")
            .and_then(|v| v.as_str())
            .or_else(|| {
                resource
                    .and_then(|r| r.get("trade_state"))
                    .and_then(|v| v.as_str())
            })
            .unwrap_or("");

        let status = match (event_type, trade_state) {
            ("TRANSACTION.SUCCESS", _) | (_, "SUCCESS") => PaymentStatus::Paid,
            ("TRANSACTION.REFUND", _) | (_, "REFUND") | (_, "REFUND_SUCCESS") => {
                PaymentStatus::Refunded
            }
            ("TRANSACTION.CLOSED", _) | (_, "CLOSED") | (_, "REVOKED") => PaymentStatus::Failed,
            _ => PaymentStatus::Pending,
        };

        // Extract the payment completion time
        let paid_at = notification_json
            .get("success_time")
            .and_then(|v| v.as_str())
            .or_else(|| {
                resource
                    .and_then(|r| r.get("success_time"))
                    .and_then(|v| v.as_str())
            })
            .and_then(|s| self.parse_wechat_datetime(s));

        Ok(PaymentNotification {
            order_id,
            trade_no,
            amount,
            currency: "CNY".to_string(),
            status,
            paid_at,
            raw: notification_json,
        })
    }

    /// Queries the status of a WeChat Pay order using the V3 Order Query API.
    ///
    /// # API Endpoint
    /// `GET https://api.mch.weixin.qq.com/v3/pay/transactions/out-trade-no/{out_trade_no}?mchid={mchid}`
    ///
    /// This endpoint returns the current state of a transaction. It is typically
    /// used as a fallback when the async notification hasn't been received or
    /// to verify the final payment status.
    ///
    /// # Response
    /// The response includes `trade_state`, `transaction_id`, `amount`, and
    /// `success_time` fields that describe the current order status.
    async fn query_order(&self, order_id: &str) -> Result<OrderStatus, PaymentError> {
        let path = format!(
            "/v3/pay/transactions/out-trade-no/{}?mchid={}",
            urlencoding::encode(order_id),
            &self.config.mch_id
        );
        let url = format!("{}{}", self.base_url(), path);
        let auth_token = self.generate_auth_token("GET", &path, "");

        let response = self
            .http_client
            .get(&url)
            .header("Authorization", &auth_token)
            .header("Accept", "application/json")
            .header("User-Agent", "labrinth-wechatpay")
            .send()
            .await
            .map_err(|e| PaymentError::Network(format!("failed to send query_order request: {e}")))?;

        let status = response.status();
        let response_text = response
            .text()
            .await
            .map_err(|e| PaymentError::Network(format!("failed to read query_order response body: {e}")))?;

        if !status.is_success() {
            return Err(PaymentError::OrderNotFound(format!(
                "wechatpay query_order failed with status {status}: {response_text}"
            )));
        }

        let response_json: serde_json::Value = serde_json::from_str(&response_text)
            .map_err(|e| PaymentError::Internal(format!("failed to parse query_order response: {e}")))?;

        // Map WeChat Pay trade states to PaymentStatus
        // Possible trade_state values:
        //   SUCCESS    - Payment successful
        //   REFUND     - Refunded
        //   NOTPAY     - Not paid yet
        //   CLOSED     - Closed
        //   REVOKED    - Revoked (user cancelled)
        //   USERPAYING - User is authenticating/paying
        //   PAYERROR   - Payment failed
        let trade_state = response_json
            .get("trade_state")
            .and_then(|v| v.as_str())
            .unwrap_or("NOTPAY");

        let status = match trade_state {
            "SUCCESS" => PaymentStatus::Paid,
            "REFUND" | "REFUND_SUCCESS" => PaymentStatus::Refunded,
            "CLOSED" | "REVOKED" | "PAYERROR" => PaymentStatus::Failed,
            _ => PaymentStatus::Pending,
        };

        let trade_no = response_json
            .get("transaction_id")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let amount = response_json
            .get("amount")
            .and_then(|a| a.get("total"))
            .and_then(|v| v.as_i64());

        let paid_at = response_json
            .get("success_time")
            .and_then(|v| v.as_str())
            .and_then(|s| self.parse_wechat_datetime(s));

        Ok(OrderStatus {
            status,
            trade_no,
            amount,
            paid_at,
        })
    }

    /// Issues a refund for a WeChat Pay order using the V3 Domestic Refund API.
    ///
    /// # API Endpoint
    /// `POST https://api.mch.weixin.qq.com/v3/refund/domestic/refunds`
    ///
    /// # Request Body (JSON)
    /// ```json
    /// {
    ///   "transaction_id": "wx_transaction_id",
    ///   "out_refund_no": "merchant_refund_id",
    ///   "reason": "用户退款",
    ///   "notify_url": "https://example.com/refund-notify",
    ///   "amount": {
    ///     "refund": 100,
    ///     "total": 100,
    ///     "currency": "CNY"
    ///   }
    /// }
    /// ```
    ///
    /// The `order_id` parameter can be either the merchant's order ID
    /// (`out_trade_no`) or the WeChat Pay transaction ID (`transaction_id`).
    ///
    /// # Refund Rules
    /// - Refunds are processed asynchronously and may take 1-3 business days.
    /// - Partial refunds are supported: set `amount` to a value less than
    ///   the original order total to issue a partial refund.
    /// - The total refund amount cannot exceed the original order amount.
    /// - Once a refund is initiated, the funds are returned to the user's
    ///   WeChat balance or original payment method.
    async fn refund(
        &self,
        order_id: &str,
        amount: Option<i64>,
    ) -> Result<(), PaymentError> {
        // First, query the order to get the transaction ID and total amount
        let order_status = self.query_order(order_id).await?;
        let transaction_id = order_status
            .trade_no
            .ok_or_else(|| PaymentError::RefundFailed("order has no transaction_id".to_string()))?;

        let total = order_status.amount.unwrap_or(0);
        let refund_amount = amount.unwrap_or(total);

        if refund_amount <= 0 {
            return Err(PaymentError::RefundFailed("refund amount must be positive".to_string()));
        }

        if refund_amount > total {
            return Err(PaymentError::RefundFailed(format!(
                "refund amount {refund_amount} exceeds original total {total}"
            )));
        }

        let path = "/v3/refund/domestic/refunds";
        let url = format!("{}{}", self.base_url(), path);

        // Generate a unique refund order ID (out_refund_no)
        let out_refund_no = format!("RF{}_{}", order_id, self.generate_nonce().get(..8).unwrap_or(""));

        let body = serde_json::json!({
            "transaction_id": transaction_id,
            "out_refund_no": out_refund_no,
            "reason": "用户退款",
            "notify_url": self.config.notify_url,
            "amount": {
                "refund": refund_amount,
                "total": total,
                "currency": "CNY"
            }
        });

        let body_str = body.to_string();
        let auth_token = self.generate_auth_token("POST", path, &body_str);

        let response = self
            .http_client
            .post(&url)
            .header("Authorization", &auth_token)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("User-Agent", "labrinth-wechatpay")
            .body(body_str)
            .send()
            .await
            .map_err(|e| PaymentError::Network(format!("failed to send refund request: {e}")))?;

        let status = response.status();

        if !status.is_success() {
            let response_text = response
                .text()
                .await
                .unwrap_or_else(|_| "could not read response body".to_string());
            return Err(PaymentError::RefundFailed(format!(
                "wechatpay refund failed with status {status}: {response_text}"
            )));
        }

        Ok(())
    }
}
