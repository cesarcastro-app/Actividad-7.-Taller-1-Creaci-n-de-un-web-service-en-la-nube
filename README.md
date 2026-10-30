# Actividad 7 · Taller 1: creación de un web service en la nube

Implementación académica del taller **Despliegue de Servicios de Red** para la asignatura *Computación Distribuida y Frameworks para Desarrollo de Aplicaciones Inteligentes*. Convierte una consulta bursátil de `yfinance` en un servicio web Flask contenerizado y automatiza su despliegue en AWS mediante Terraform, Amazon ECR y una instancia EC2 administrada con AWS Systems Manager.

**Autor:** Cesar Castro

## Contenido

| Ruta | Propósito |
|---|---|
| `app.py` | Rutas HTML, API JSON y health check. |
| `stock_service.py` | Validación y consulta de información bursátil. |
| `templates/` | Interfaz web del servicio. |
| `Dockerfile` | Imagen de producción con Gunicorn y usuario sin privilegios. |
| `compose.yaml` | Ejecución local del contenedor. |
| `tests/` | Pruebas automáticas sin depender de Yahoo Finance. |
| `infra/` | VPC, ECR, IAM, EC2, SSM y Elastic IP en Terraform. |
| `scripts/deploy.ps1` | Construcción, publicación y despliegue automatizado. |
| `scripts/validate.ps1` | Pruebas y validaciones locales. |
| `scripts/stop.ps1` | Detención y verificación de EC2 sin eliminar infraestructura. |
| `scripts/destroy.ps1` | Eliminación controlada de los recursos AWS. |
| `docs/ARQUITECTURA.md` | Diseño, flujo y decisiones técnicas. |
| `docs/GUIA_DESPLIEGUE.md` | Procedimiento completo de despliegue y operación. |

## Inicio rápido local

```powershell
docker compose up --build
```

Visite `http://localhost:8000` o consulte la API:

```text
GET /api/stocks/GOOGL?start=2025-01-01&end=2025-02-01
GET /health
```

Para crear la infraestructura, continúe con [la guía de despliegue](docs/GUIA_DESPLIEGUE.md). La arquitectura está explicada en [ARQUITECTURA.md](docs/ARQUITECTURA.md).

## Avisos

- El contenido es educativo y no constituye asesoría financiera.
- Yahoo Finance es un servicio externo; sus datos y disponibilidad no están controlados por esta aplicación.
- Ejecutar Terraform crea recursos reales de AWS que pueden producir cargos.
