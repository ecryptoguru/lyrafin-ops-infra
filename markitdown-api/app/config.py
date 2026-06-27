from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    api_key: str = "local-dev-token"
    azure_document_intelligence_endpoint: str = ""
    azure_document_intelligence_key: str = ""
    max_file_size_mb: int = 50
    conversion_timeout_seconds: int = 120

    model_config = {"env_prefix": "MARKITDOWN_", "env_file": ".env", "extra": "ignore"}

    @property
    def max_file_size_bytes(self) -> int:
        return self.max_file_size_mb * 1024 * 1024


settings = Settings()

ALLOWED_MIME_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel",
    "application/msword",
    "application/vnd.ms-powerpoint",
    "text/csv",
    "text/html",
    "text/plain",
    "text/markdown",
    "application/json",
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    "image/bmp",
    "image/tiff",
    "audio/mpeg",
    "audio/wav",
    "video/mp4",
    "application/zip",
}

ALLOWED_EXTENSIONS = {
    ".pdf", ".docx", ".pptx", ".xlsx", ".xls", ".doc", ".ppt",
    ".csv", ".html", ".htm", ".txt", ".md", ".json",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif",
    ".mp3", ".wav", ".mp4",
    ".zip",
}
