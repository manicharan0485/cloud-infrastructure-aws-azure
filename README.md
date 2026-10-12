# ☁️ Cloud Infrastructure — AWS & Azure

Production-grade Terraform configurations and CI/CD pipeline templates for multi-cloud infrastructure deployment on AWS and Azure.

---

## 📁 Repository Structure

```
cloud-infrastructure-aws-azure/
├── terraform/
│   ├── aws/
│   │   └── main.tf           # EC2, VPC, S3, RDS, IAM (variables and outputs inline)
│   └── azure/
│       └── main.tf           # Azure Backup Vault, VM, Networking (variables inline)
├── pipelines/
│   └── jenkins_pipeline.groovy     # Jenkins declarative pipeline
└── README.md
```

---

## 🛠️ Technologies

| Category | Tools |
|----------|-------|
| Cloud | AWS (EC2, S3, RDS, VPC, IAM), Microsoft Azure (IaaS/PaaS) |
| IaC | Terraform >= 1.0 |
| CI/CD | Jenkins |
| Containers | Docker, Kubernetes |
| OS | Ubuntu 22.04, Windows Server 2022 |

---

## 🚀 Quick Start

```bash
# AWS
cd terraform/aws/
terraform init
terraform plan -var="environment=production"
terraform apply -var="environment=production"

# Azure
cd terraform/azure/
terraform init
terraform plan -var="environment=production"
terraform apply -var="environment=production"
```

---

## 🔒 Security Defaults

- All S3 buckets: public access blocked, versioning enabled, AES-256 encryption
- RDS: encryption at rest, no public accessibility, Multi-AZ for production
- IAM: least-privilege policies, no wildcard permissions
- Azure: Backup Vault with soft-delete enabled, RBAC-based access
- All secrets via AWS Secrets Manager / Azure Key Vault — never in code

---

## 👤 Author

**Manicharan Ravi** — IT Specialist & Cloud Engineer  
📧 manicharan.ravi999@gmail.com  
🔗 [linkedin.com/in/manicharan-ravi](https://linkedin.com/in/manicharan-ravi)
