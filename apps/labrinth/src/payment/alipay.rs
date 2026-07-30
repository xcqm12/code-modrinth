//! Alipay (支付宝) payment gateway implementation.
//!
//! Implements the [`PaymentGateway`] trait for the Alipay Open API using
//! RSA-SHA256 (RSA2) signing.  All API calls use POST with
//! `application/x-www-form-urlencoded` parameters.
//!
//! # Dependencies
//!
//! Add to the workspace `Cargo.toml`:
//! ```toml
//! rsa = { version = "0.9", features = ["pkcs8", "pem"] }
//! ```
//!
//! # API flow
//!
//! 1. **create_order** – builds a signed redirect URL for `alipay.trade.page.pay`
//!    and also calls `alipay.trade.precreate` to obtain a QR code.
//! 2. **verify_notification** – parses the POST form body Alipay sends to the
//!    `notify_url`, verifies the RSA signature, and returns a [`PaymentNotification`].
//! 3. **query_order** – calls `alipay.trade.query` for the current trade state.
//! 4. **refund** – calls `alipay.trade.refund` (queries the full amount when
//!    `amount` is `None`).

use std::collections::HashMap;

use async_trait::async_trait;
use base64::Engine;
use chrono::{DateTime, Utc};
use rsa::pkcs1v15::{Signature, SigningKey, VerifyingKey};
use rsa::signature::{SignatureEncoding, Signer, Verifier};
use rsa::{RsaPrivateKey, RsaPublicKey};
use serde_json::Value;
use sha2::Sha256;

use super::{
    CreateOrderRequest, CreateOrderResponse, OrderStatus, PaymentError, PaymentGateway,
    PaymentNotification, PaymentStatus,
};

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Configuration for the Alipay payment gateway.
pub struct AlipayConfig {
    /// Alipay Open Platform app ID.
    pub app_id: String,
    /// Merchant RSA private key in PKCS#8 PEM format.
    pub private_key: String,
    /// Alipay's RSA public key in PEM format (used to verify callbacks).
    pub alipay_public_key: String,
    /// Alipay API gateway URL.
    ///
    /// - Sandbox: `https://openapi-sandbox.dl.alipaydev.com/gateway.do`
    /// - Production: `https://openapi.alipay.com/gateway.do`
    pub gateway_url: String,
    /// URL that receives async payment notifications via POST.
    pub notify_url: String,
    /// URL the user is redirected to after payment.
    pub return_url: String,
}

// ---------------------------------------------------------------------------
// Gateway
// ---------------------------------------------------------------------------

/// Alipay payment gateway.
pub struct AlipayGateway {
    config: AlipayConfig,
    client: reqwest::Client,
}

impl AlipayGateway {
    /// Creates a new Alipay gateway.
    pub fn new(config: AlipayConfig) -> Self {
        Self {
            config,
            client: reqwest::Client::new(),
        }
    }

    // ---- parameter helpers -------------------------------------------------

    /// Returns the common parameter set for any Alipay API method, **already
    /// sorted alphabetically by key** (required for signing).
    fn common_params(&self, method: &str, biz_content: &str) -> Vec<(String, String)> {
        let ts = Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
        let mut params = vec![
            ("app_id".into(), self.config.app_id.clone()),
            ("biz_content".into(), biz_content.into()),
            ("charset".into(), "utf-8".into()),
            ("format".into(), "JSON".into()),
            ("method".into(), method.into()),
            ("notify_url".into(), self.config.notify_url.clone()),
            ("sign_type".into(), "RSA2".into()),
            ("timestamp".into(), ts),
            ("version".into(), "1.0".into()),
        ];
        params.sort_by(|a, b| a.0.cmp(&b.0));
        params
    }

    /// Builds the canonical sign string (`key1=value1&key2=value2&…`) from a
    /// **pre-sorted** parameter list.
    fn sign_string(params: &[(String, String)]) -> String {
        let mut buf = String::new();
        for (i, (k, v)) in params.iter().enumerate() {
            if i > 0 {
                buf.push('&');
            }
            buf.push_str(k);
            buf.push('=');
            buf.push_str(v);
        }
        buf
    }

    /// RSA-SHA256 sign `data` with the merchant private key, returning
    /// standard Base64.
    fn sign_data(&self, data: &str) -> Result<String, PaymentError> {
        let sk = RsaPrivateKey::from_pkcs8_pem(&self.config.private_key).map_err(|e| {
            PaymentError::Internal(format!("failed to parse alipay private key: {e}"))
        })?;
        let signing_key = SigningKey::<Sha256>::new(sk);
        let sig = signing_key.sign(data.as_bytes());
        Ok(base64::engine::general_purpose::STANDARD.encode(sig.to_bytes()))
    }

    /// Signs the given (already sorted) parameters **in place**, appending the
    /// `sign` entry.
    fn attach_signature(&self, params: &mut Vec<(String, String)>) -> Result<(), PaymentError> {
        let s = Self::sign_string(params);
        let sig = self.sign_data(&s)?;
        params.push(("sign".into(), sig));
        Ok(())
    }

    /// Verifies `data` against `signature_b64` using Alipay's public key.
    fn verify_data(&self, data: &str, signature_b64: &str) -> Result<bool, PaymentError> {
        let pk = RsaPublicKey::from_public_key_pem(&self.config.alipay_public_key).map_err(
            |e| PaymentError::Internal(format!("failed to parse alipay public key: {e}")),
        )?;
        let verifying_key = VerifyingKey::<Sha256>::new(pk);
        let sig_bytes = base64::engine::general_purpose::STANDARD
            .decode(signature_b64)
            .map_err(|_| PaymentError::InvalidSignature)?;
        let sig = Signature::try_from(sig_bytes.as_slice()).map_err(|_| PaymentError::InvalidSignature)?;
        Ok(verifying_key.verify(data.as_bytes(), &sig).is_ok())
    }

    // ---- raw API call ------------------------------------------------------

    /// POSTs a signed request to the Alipay gateway.
    ///
    /// On success the full JSON response is returned; the response signature is
    /// verified automatically and API-level errors are converted to
    /// [`PaymentError::Internal`].
    async fn call_api(&self, method: &str, biz_content: Value) -> Result<Value, PaymentError> {
        let bc = serde_json::to_string(&biz_content)
            .map_err(|e| PaymentError::Internal(e.to_string()))?;
        let mut params = self.common_params(method, &bc);
        self.attach_signature(&mut params)?;

        let resp = self
            .client
            .post(&self.config.gateway_url)
            .form(&params)
            .send()
            .await
            .map_err(|e| PaymentError::Network(format!("alipay request failed: {e}")))?;

        let text = resp
            .text()
            .await
            .map_err(|e| PaymentError::Network(format!("alipay response read error: {e}")))?;

        let json: Value =
            serde_json::from_str(&text).map_err(|e| PaymentError::Internal(e.to_string()))?;

        // Identify the response envelope key, e.g. "alipay_trade_precreate_response".
        let rkey = response_key(method);
        let body = json
            .get(&rkey)
            .and_then(|v| v.as_object())
            .ok_or_else(|| PaymentError::Internal(format!("missing `{rkey}` in response")))?;

        // Verify the response signature if present.
        if let Some(sign) = json.get("sign").and_then(|v| v.as_str()) {
            let mut pairs: Vec<(String, String)> = body
                .iter()
                .map(|(k, v)| {
                    let val = match v {
                        Value::String(s) => s.clone(),
                        other => other.to_string(),
                    };
                    (k.clone(), val)
                })
                .collect();
            pairs.sort_by(|a, b| a.0.cmp(&b.0));
            let ss = Self::sign_string(&pairs);
            if !self.verify_data(&ss, sign).unwrap_or(false) {
                return Err(PaymentError::InvalidSignature);
            }
        }

        // Check the business code (10000 = success).
        let code = body.get("code").and_then(|v| v.as_str()).unwrap_or("0");
        if code != "10000" {
            let msg = body.get("msg").and_then(|v| v.as_str()).unwrap_or("?");
            let sub = body.get("sub_msg").and_then(|v| v.as_str());
            let detail = match sub {
                Some(s) => format!("{msg}: {s}"),
                None => msg.to_string(),
            };
            return Err(PaymentError::Internal(format!("alipay error (code={code}): {detail}")));
        }

        Ok(json)
    }

    // ---- time helpers ------------------------------------------------------

    /// Parses an Alipay timestamp (`yyyy-MM-dd HH:mm:ss`, Asia/Shanghai) into
    /// `DateTime<Utc>`.
    fn parse_time(s: &str) -> Option<DateTime<Utc>> {
        let naive = chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S").ok()?;
        let dt = naive.and_local_timezone(chrono::FixedOffset::east_opt(8 * 3600)?)?;
        Some(dt.with_timezone(&Utc))
    }

    /// Converts an Alipay trade status string into [`PaymentStatus`].
    fn trade_status(kind: &str) -> PaymentStatus {
        match kind {
            "WAIT_BUYER_PAY" => PaymentStatus::Pending,
            "TRADE_CLOSED" => PaymentStatus::Failed,
            "TRADE_SUCCESS" | "TRADE_FINISHED" => PaymentStatus::Paid,
            _ => PaymentStatus::Pending,
        }
    }
}

// ---- free helpers ----------------------------------------------------------

/// Converts an Alipay API method name to the response JSON key.
///
/// Example: `alipay.trade.precreate` → `alipay_trade_precreate_response`.
fn response_key(method: &str) -> String {
    format!("{}_response", method.replace('.', "_"))
}

// ---- trait implementation --------------------------------------------------

#[async_trait]
impl PaymentGateway for AlipayGateway {
    /// Creates an order with Alipay.
    ///
    /// 1. Calls `alipay.trade.precreate` to obtain a QR code (in-store / mobile).
    /// 2. Builds a signed redirect URL for `alipay.trade.page.pay` (desktop web).
    ///
    /// Both results are returned so the frontend can choose the most appropriate
    /// payment method.
    async fn create_order(&self, order: CreateOrderRequest) -> Result<CreateOrderResponse, PaymentError> {
        // Amount in *yuan* (Alipay expects 2-decimal string).
        let amount_yuan = format!("{:.2}", order.amount as f64 / 100.0);

        // ── QR code (alipay.trade.precreate) ──────────────────────────────
        let pre_biz = serde_json::json!({
            "out_trade_no": order.order_id,
            "total_amount": amount_yuan,
            "subject": order.subject,
            "body": order.description,
            "timeout_express": "30m",
        });

        // Precreate is best-effort: if it fails we still return the web URL.
        let (qr_code, trade_no, raw) = match self.call_api("alipay.trade.precreate", pre_biz).await {
            Ok(resp) => {
                let body = resp
                    .get(&response_key("alipay.trade.precreate"))
                    .and_then(|v| v.as_object());
                let qr = body
                    .and_then(|b| b.get("qr_code"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                let tn = body
                    .and_then(|b| b.get("trade_no"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                (qr, tn, resp)
            }
            Err(e) => {
                // Log the error but continue so the web fallback still works.
                tracing::warn!("alipay precreate failed (falling back to page pay): {e}");
                (None, None, Value::Null)
            }
        };

        // ── Web redirect URL (alipay.trade.page.pay) ──────────────────────
        let page_biz = serde_json::json!({
            "out_trade_no": order.order_id,
            "product_code": "FAST_INSTANT_TRADE_PAY",
            "total_amount": amount_yuan,
            "subject": order.subject,
            "body": order.description,
            "qr_pay_mode": "4",
        });

        let bc = serde_json::to_string(&page_biz)
            .map_err(|e| PaymentError::Internal(e.to_string()))?;
        let mut params = self.common_params("alipay.trade.page.pay", &bc);
        self.attach_signature(&mut params)?;

        let qs: String = params
            .iter()
            .map(|(k, v)| format!("{}={}", k, urlencoding::encode(v)))
            .collect::<Vec<_>>()
            .join("&");
        let payment_url = format!("{}?{}", self.config.gateway_url, qs);

        Ok(CreateOrderResponse {
            payment_url: Some(payment_url),
            qr_code,
            trade_no,
            raw,
        })
    }

    /// Verifies an Alipay async payment notification.
    ///
    /// Alipay POSTs `application/x-www-form-urlencoded` data to the registered
    /// `notify_url`.  This method:
    ///
    /// 1. Parses the form body.
    /// 2. Rebuilds the sign string (all fields except `sign` and `sign_type`).
    /// 3. Verifies the RSA-SHA256 signature with Alipay's public key.
    /// 4. Extracts trade information into a [`PaymentNotification`].
    async fn verify_notification(
        &self,
        body: &str,
        _headers: &[(String, String)],
    ) -> Result<PaymentNotification, PaymentError> {
        // Parse form-encoded body.
        let pairs: Vec<(String, String)> = url::form_urlencoded::parse(body.as_bytes())
            .map(|(k, v)| (k.into_owned(), v.into_owned()))
            .collect();

        // Extract the signature.
        let sign = pairs
            .iter()
            .find(|(k, _)| k == "sign")
            .map(|(_, v)| v.clone())
            .ok_or(PaymentError::InvalidSignature)?;

        // Build the string-to-sign (exclude sign and sign_type).
        let sign_pairs: Vec<(String, String)> = pairs
            .iter()
            .filter(|(k, _)| k != "sign" && k != "sign_type")
            .cloned()
            .collect();
        let ss = Self::sign_string(&sign_pairs);

        if !self.verify_data(&ss, &sign).unwrap_or(false) {
            return Err(PaymentError::InvalidSignature);
        }

        let map: HashMap<String, String> = pairs.into_iter().collect();

        let order_id = map
            .get("out_trade_no")
            .cloned()
            .ok_or(PaymentError::InvalidSignature)?;
        let trade_no = map
            .get("trade_no")
            .cloned()
            .ok_or(PaymentError::InvalidSignature)?;

        let amount_yuan: f64 = map.get("total_amount").and_then(|s| s.parse().ok()).unwrap_or(0.0);
        let amount = (amount_yuan * 100.0) as i64;

        let mut status = Self::trade_status(map.get("trade_status").map(|s| s.as_str()).unwrap_or(""));
        // If the trade was closed but a refund timestamp exists it is a refund.
        if matches!(status, PaymentStatus::Failed) && map.contains_key("gmt_refund") {
            status = PaymentStatus::Refunded;
        }

        let paid_at = map.get("gmt_payment").and_then(|s| Self::parse_time(s));

        let raw: Value = map
            .iter()
            .map(|(k, v)| (k.clone(), Value::String(v.clone())))
            .collect::<serde_json::Map<_, _>>()
            .into();

        Ok(PaymentNotification {
            order_id,
            trade_no,
            amount,
            currency: "CNY".to_string(),
            status,
            paid_at,
            raw,
        })
    }

    /// Queries the current order status via `alipay.trade.query`.
    async fn query_order(&self, order_id: &str) -> Result<OrderStatus, PaymentError> {
        let biz = serde_json::json!({ "out_trade_no": order_id });
        let resp = self.call_api("alipay.trade.query", biz).await?;

        let body = resp
            .get(&response_key("alipay.trade.query"))
            .and_then(|v| v.as_object())
            .ok_or_else(|| PaymentError::Internal("missing query response body".into()))?;

        let status = Self::trade_status(
            body.get("trade_status")
                .and_then(|v| v.as_str())
                .unwrap_or(""),
        );
        let trade_no = body
            .get("trade_no")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());

        let amount_yuan: f64 = body
            .get("total_amount")
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.0);
        let amount = (amount_yuan * 100.0) as i64;

        let paid_at = body
            .get("send_pay_date")
            .and_then(|v| v.as_str())
            .and_then(Self::parse_time);

        Ok(OrderStatus {
            status,
            trade_no,
            amount: Some(amount),
            paid_at,
        })
    }

    /// Refunds a transaction.
    ///
    /// When `amount` is `None` the full order amount is refunded (the gateway
    /// first queries the order to obtain the original total).
    async fn refund(&self, order_id: &str, amount: Option<i64>) -> Result<(), PaymentError> {
        let refund_amount = match amount {
            Some(a) => format!("{:.2}", a as f64 / 100.0),
            None => {
                // Query the full amount first.
                let status = self.query_order(order_id).await?;
                let full = status.amount.unwrap_or(0);
                if full <= 0 {
                    return Err(PaymentError::RefundFailed(
                        "cannot determine refund amount: order not found or amount is zero".into(),
                    ));
                }
                format!("{:.2}", full as f64 / 100.0)
            }
        };

        let biz = serde_json::json!({
            "out_trade_no": order_id,
            "refund_amount": refund_amount,
        });

        let resp = self.call_api("alipay.trade.refund", biz).await?;

        let body = resp
            .get(&response_key("alipay.trade.refund"))
            .and_then(|v| v.as_object())
            .ok_or_else(|| PaymentError::RefundFailed("missing refund response body".into()))?;

        let code = body.get("code").and_then(|v| v.as_str()).unwrap_or("0");
        if code != "10000" {
            let msg = body.get("msg").and_then(|v| v.as_str()).unwrap_or("?");
            return Err(PaymentError::RefundFailed(msg.into()));
        }

        let changed = body
            .get("fund_change")
            .and_then(|v| v.as_str())
            .unwrap_or("N");
        if changed != "Y" {
            return Err(PaymentError::RefundFailed(
                "alipay did not change funds for this refund".into(),
            ));
        }

        Ok(())
    }

    fn name(&self) -> &'static str {
        "alipay"
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_string_is_sorted() {
        let mut p = vec![
            ("z".into(), "1".into()),
            ("a".into(), "2".into()),
        ];
        p.sort_by(|a, b| a.0.cmp(&b.0));
        let s = AlipayGateway::sign_string(&p);
        assert_eq!(s, "a=2&z=1");
    }

    #[test]
    fn response_key_format() {
        assert_eq!(
            response_key("alipay.trade.precreate"),
            "alipay_trade_precreate_response"
        );
        assert_eq!(
            response_key("alipay.trade.page.pay"),
            "alipay_trade_page_pay_response"
        );
    }

    #[test]
    fn parse_time_utc8_to_utc() {
        let dt = AlipayGateway::parse_time("2024-06-15 14:30:00");
        assert!(dt.is_some());
        // 14:30 CST (UTC+8) = 06:30 UTC
        assert_eq!(dt.unwrap().format("%H:%M:%S").to_string(), "06:30:00");
    }

    #[test]
    fn trade_status_mapping() {
        assert!(matches!(AlipayGateway::trade_status("WAIT_BUYER_PAY"), PaymentStatus::Pending));
        assert!(matches!(AlipayGateway::trade_status("TRADE_CLOSED"), PaymentStatus::Failed));
        assert!(matches!(AlipayGateway::trade_status("TRADE_SUCCESS"), PaymentStatus::Paid));
        assert!(matches!(AlipayGateway::trade_status("TRADE_FINISHED"), PaymentStatus::Paid));
    }

    #[test]
    fn parse_time_invalid() {
        assert!(AlipayGateway::parse_time("not-a-date").is_none());
    }
}
