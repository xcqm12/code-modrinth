use actix_web::{HttpResponse, get};
use serde_json::json;

fn build_info() -> serde_json::Value {
    json!({
        "name": "Bbsmc-labrinth",
        "version": env!("CARGO_PKG_VERSION"),
        "documentation": "https://docs.bbsmc.org.cn",
        "about": "Welcome traveler!",

        "build_info": {
            "comp_date": env!("COMPILATION_DATE"),
            "git_hash": option_env!("GIT_HASH").unwrap_or("unknown"),
            "profile": env!("COMPILATION_PROFILE"),
        }
    })
}

#[get("/")]
pub async fn index_get() -> HttpResponse {
    HttpResponse::Ok().json(build_info())
}

#[get("/build")]
pub async fn build_get() -> HttpResponse {
    HttpResponse::Ok().json(build_info())
}
