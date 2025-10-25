# tfstate

Terraform State Manager

## Init

```bash
./init.sh main default
```

```bash
export ACCESS_KEY=$(terraform output s3_access_key)
export SECRET_KEY=$(terraform output s3_secret_key)
```

```bash
terraform init -backend-config="access_key=$ACCESS_KEY" -backend-config="secret_key=$SECRET_KEY"
```
