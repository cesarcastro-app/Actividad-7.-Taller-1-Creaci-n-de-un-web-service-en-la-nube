variable "aws_region" {
  description = "Región de AWS donde se crearán todos los recursos."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo corto usado para nombrar y etiquetar recursos."
  type        = string
  default     = "stock-market"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "Use entre 3 y 31 caracteres: minúsculas, números y guiones."
  }
}

variable "instance_type" {
  description = "Tipo de instancia EC2; compruebe costos y elegibilidad Free Tier."
  type        = string
  default     = "t3.micro"
}

variable "http_cidr" {
  description = "Red autorizada a consumir HTTP. 0.0.0.0/0 publica el taller en Internet."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.http_cidr))
    error_message = "http_cidr debe ser un bloque IPv4 CIDR válido."
  }
}

variable "default_ticker" {
  description = "Símbolo que aparece inicialmente en la interfaz web."
  type        = string
  default     = "GOOGL"
}
