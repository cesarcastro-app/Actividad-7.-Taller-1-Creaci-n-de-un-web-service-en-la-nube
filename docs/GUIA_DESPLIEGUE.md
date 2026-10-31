# Guía de despliegue en AWS

Esta guía crea recursos facturables. Revise la calculadora y la elegibilidad de Free Tier de su cuenta antes de ejecutar `terraform apply`.

## 1. Prerrequisitos

Instale en Windows:

- Docker Desktop con el motor iniciado.
- Terraform 1.6 o posterior.
- AWS CLI v2.
- PowerShell 7 recomendado.
- Python 3.13 para las pruebas locales.

Configure AWS CLI con una identidad IAM o acceso federado; no use las credenciales del usuario raíz:

```powershell
aws configure
aws sts get-caller-identity
```

La identidad que ejecuta Terraform necesita administrar EC2, VPC, EIP, ECR, IAM y SSM. La identidad que publica necesita además permisos de escritura en ECR y `ssm:SendCommand`/`ssm:GetCommandInvocation`.

## 2. Probar localmente

```powershell
docker compose up --build
```

Abra `http://localhost:8000` y compruebe:

```powershell
Invoke-RestMethod http://localhost:8000/health
Invoke-RestMethod 'http://localhost:8000/api/stocks/GOOGL?start=2025-01-01&end=2025-02-01'
docker compose down
```

## 3. Configurar Terraform

```powershell
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
```

Edite `infra/terraform.tfvars`. Opciones relevantes:

- `aws_region`: región usada también por ECR y SSM.
- `instance_type`: `t3.micro` es el valor inicial, pero puede generar cargos.
- `http_cidr`: use su IP con `/32` si no necesita acceso público general.
- `project_name`: debe ser único dentro de los recursos IAM de la cuenta.

Inicialice y revise antes de crear:

```powershell
terraform -chdir=infra init
terraform -chdir=infra fmt -check
terraform -chdir=infra validate
terraform -chdir=infra plan -out=tfplan
```

Lea el plan. Si coincide con lo esperado:

```powershell
terraform -chdir=infra apply tfplan
terraform -chdir=infra output
```

La preparación inicial de EC2 suele tardar varios minutos. No es necesario crear una llave SSH: la administración se realiza mediante Systems Manager.

## 4. Publicar y desplegar

Ejecute desde la raíz del proyecto:

```powershell
.\scripts\deploy.ps1
```

El script requiere que `terraform apply` haya creado la infraestructura y que el estado conserve sus salidas. Si anteriormente ejecutó `terraform destroy`, primero vuelva a generar y aplicar un plan:

```powershell
terraform -chdir=infra plan -out=tfplan
terraform -chdir=infra apply tfplan
```

El script genera una etiqueta UTC, construye la imagen, inicia sesión en ECR mediante un token temporal, publica la imagen, espera a SSM y actualiza el contenedor. Para una versión explícita:

```powershell
.\scripts\deploy.ps1 -ImageTag 'v1.0.0' -DefaultTicker 'AMZN'
```

Las etiquetas de ECR son inmutables: no reutilice `v1.0.0`; publique `v1.0.1`.

Si la imagen ya se publicó pero falló únicamente la actualización de EC2, reanude sin volver a subirla:

```powershell
.\scripts\deploy.ps1 -ImageTag 'v1.0.1' -SkipImagePush
```

Abra la URL reportada o recupérela después:

```powershell
$url = terraform -chdir=infra output -raw application_url
Invoke-RestMethod "$url/health"
Start-Process $url
```

## 5. Operación y diagnóstico

Compruebe que la instancia está administrada por SSM:

```powershell
$region = terraform -chdir=infra output -raw aws_region
$instance = terraform -chdir=infra output -raw instance_id
aws ssm describe-instance-information --region $region --filters "Key=InstanceIds,Values=$instance"
```

Puede abrir una sesión administrativa sin SSH:

```powershell
aws ssm start-session --region $region --target $instance
```

Dentro de EC2, los comandos útiles son:

```bash
sudo cloud-init status --long
sudo tail -n 200 /var/log/cloud-init-output.log
sudo docker ps
sudo docker logs --tail 200 stock-market
curl --fail http://127.0.0.1/health
```

Si ECR devuelve `no basic auth credentials`, verifique que el login y el repositorio usan la misma región. Los tokens de autenticación de ECR caducan; el script solicita uno nuevo en cada despliegue.

## 6. Actualizar la aplicación

Modifique y pruebe el código. Publique siempre una etiqueta nueva:

```powershell
.\scripts\validate.ps1
.\scripts\deploy.ps1 -ImageTag 'v1.1.0'
```

El contenedor tiene `--restart unless-stopped`, por lo que reinicia con Docker o con la instancia.

## 7. Detener EC2 sin eliminar la infraestructura

Para suspender el cómputo y verificar que la instancia llegó al estado `stopped`:

```powershell
.\scripts\stop.ps1
```

El script puede ejecutarse varias veces sin error. Conserva ECR, VPC, Elastic IP, el volumen EBS y el estado de Terraform. Estos recursos pueden seguir generando cargos aunque EC2 esté detenida.

## 8. Eliminar recursos y detener costos

ECR, EC2, volúmenes y la Elastic IP pueden generar cargos. Cuando termine la actividad:

```powershell
.\scripts\destroy.ps1
```

Confirme la operación y verifique que Terraform termina con `Destroy complete`. Como comprobación adicional:

```powershell
terraform -chdir=infra show
aws ec2 describe-instances --region $region --instance-ids $instance
```

El archivo de estado local es necesario para actualizar o destruir la práctica. No lo borre antes de `terraform destroy` y no lo publique en un repositorio.
El archivo `infra/.terraform.lock.hcl`, en cambio, sí debe versionarse: fija la selección del proveedor validada para el proyecto.
