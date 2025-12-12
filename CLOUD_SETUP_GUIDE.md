# Cloud Provider Setup Guide
## Dot Sync - Complete Configuration Instructions

**Last Updated:** December 11, 2025

---

## 🌥️ **All 4 Cloud Providers Now Supported**

Dot Sync supports all major cloud storage providers with complete implementations:
- ✅ **AWS S3** - Full Signature V4 authentication
- ✅ **Azure Blob Storage** - OAuth 2.0 with client credentials
- ✅ **Google Cloud Storage** - Service account authentication
- ✅ **iCloud Drive** - System authentication (easiest!)

---

## 🍎 **iCloud Drive (Easiest Setup)**

### Why Choose iCloud?
- ✅ **No credentials needed** - Uses your Apple ID
- ✅ **Free 5GB** (or more with paid iCloud+ plan)
- ✅ **Automatic encryption** - Apple handles security
- ✅ **Works immediately** - No API setup required
- ✅ **Mac-to-Mac** - Perfect for multiple Macs
- ⚠️ **Mac only** - Won't work with Linux/Windows

### Setup (30 seconds):

1. **Open Dot Sync Preferences** (⌘,)
2. **Go to "Cloud Storage" tab**
3. **Select:** iCloud Drive
4. **Folder:** Choose where to store (default: "Dot Sync")
5. **Click "Test Connection"** - Should work immediately
6. **Click "Save"**

### How It Works:
- Files stored in: `~/Library/Mobile Documents/com~apple~CloudDocs/Dot Sync/`
- Automatic sync via iCloud
- Uses NSFileCoordinator for safe file operations
- No bandwidth limits (Apple handles sync)

### Troubleshooting:
- **"Not configured"** - Check iCloud is enabled in System Settings
- **"Authentication failed"** - Sign in to iCloud in System Settings
- **Files not syncing** - Give Dot Sync Full Disk Access

---

## 🔶 **AWS S3 (Most Popular)**

### Why Choose AWS?
- ✅ **Flexible** - Works from any device (Mac, Linux, Windows)
- ✅ **Cheap** - $0.023/GB/month (~$0.02/month for typical dotfiles)
- ✅ **Fast** - Global edge locations
- ✅ **Reliable** - 99.999999999% durability
- ✅ **Version control** - Built-in versioning available

### Prerequisites:

1. **AWS Account** - https://aws.amazon.com/
2. **Create S3 Bucket:**
   ```bash
   aws s3 mb s3://your-dotfiles-bucket
   ```

3. **Create IAM User** for Dot Sync:
   ```bash
   # Create user
   aws iam create-user --user-name dotsync-user

   # Attach S3 policy
   aws iam attach-user-policy --user-name dotsync-user \
     --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

   # Create access key
   aws iam create-access-key --user-name dotsync-user
   # Save the AccessKeyId and SecretAccessKey
   ```

### Setup in Dot Sync:

1. **Open Preferences** (⌘,) → Cloud Storage tab
2. **Select:** AWS S3
3. **Enter:**
   - **Bucket Name:** your-dotfiles-bucket
   - **Region:** us-east-1 (or your bucket's region)
   - **Access Key ID:** AKIA... (from IAM user)
   - **Secret Access Key:** (from IAM user)
4. **Click "Test Connection"** - Should show ✅
5. **Click "Save"**

### Security Notes:
- Credentials stored in macOS Keychain
- Uses AWS Signature V4 (industry standard)
- Supports server-side encryption (SSE-S3)
- Enable bucket versioning for history

### Cost Estimate:
- **Storage:** ~10MB of dotfiles = $0.0002/month
- **Requests:** ~100 sync operations = $0.0005/month
- **Total:** ~$0.001/month (basically free!)

---

## 🔷 **Azure Blob Storage**

### Why Choose Azure?
- ✅ **Microsoft ecosystem** - Good for Azure users
- ✅ **Hot/Cool tiers** - Optimize costs
- ✅ **Geo-redundant** - Multiple datacenter copies
- ✅ **Enterprise features** - RBAC, private endpoints

### Prerequisites:

1. **Azure Account** - https://azure.microsoft.com/
2. **Create Storage Account:**
   ```bash
   az storage account create \
     --name yourdotsync \
     --resource-group dotfiles-rg \
     --location eastus \
     --sku Standard_LRS
   ```

3. **Create Container:**
   ```bash
   az storage container create \
     --name dotfiles \
     --account-name yourdotsync
   ```

4. **Create Service Principal:**
   ```bash
   # Create app registration
   az ad sp create-for-rbac --name dotsync-app \
     --role "Storage Blob Data Contributor" \
     --scopes /subscriptions/{subscription-id}/resourceGroups/dotfiles-rg

   # Save the output:
   # - appId (Client ID)
   # - password (Client Secret)
   # - tenant (Tenant ID)
   ```

### Setup in Dot Sync:

1. **Open Preferences** (⌘,) → Cloud Storage tab
2. **Select:** Azure Blob Storage
3. **Enter:**
   - **Storage Account:** yourdotsync
   - **Container:** dotfiles
   - **Tenant ID:** (from service principal)
   - **Client ID:** (from service principal)
   - **Client Secret:** (from service principal)
4. **Click "Test Connection"**
5. **Click "Save"**

### Authentication:
- Uses OAuth 2.0 client credentials flow
- Token automatically refreshed
- Stored in macOS Keychain

---

## 🔴 **Google Cloud Storage**

### Why Choose GCP?
- ✅ **Google ecosystem** - Good for GCP users
- ✅ **Nearline/Coldline** - Cost optimization
- ✅ **Global network** - Google's fast infrastructure
- ✅ **Free tier** - 5GB free storage

### Prerequisites:

1. **Google Cloud Account** - https://cloud.google.com/
2. **Create Project** (if needed):
   ```bash
   gcloud projects create dotsync-project
   gcloud config set project dotsync-project
   ```

3. **Enable Cloud Storage API:**
   ```bash
   gcloud services enable storage-api.googleapis.com
   ```

4. **Create Bucket:**
   ```bash
   gsutil mb -l us-east1 gs://your-dotfiles-bucket/
   ```

5. **Create Service Account:**
   ```bash
   gcloud iam service-accounts create dotsync-sa \
     --display-name="Dot Sync Service Account"

   # Grant storage permissions
   gcloud projects add-iam-policy-binding dotsync-project \
     --member="serviceAccount:dotsync-sa@dotsync-project.iam.gserviceaccount.com" \
     --role="roles/storage.objectAdmin"

   # Create key
   gcloud iam service-accounts keys create ~/dotsync-key.json \
     --iam-account=dotsync-sa@dotsync-project.iam.gserviceaccount.com
   ```

### Setup in Dot Sync:

1. **Open Preferences** (⌘,) → Cloud Storage tab
2. **Select:** Google Cloud Storage
3. **Enter:**
   - **Bucket Name:** your-dotfiles-bucket
   - **Project ID:** dotsync-project
   - **Service Account Key:** (paste entire JSON from ~/dotsync-key.json)
4. **Click "Test Connection"**
5. **Click "Save"**

### Notes:
- Service account key is JSON (entire file content)
- **Important:** Delete ~/dotsync-key.json after setup
- Uses OAuth 2.0 with JWT bearer tokens

---

## 🔧 **S3-Compatible Providers**

Dot Sync also supports S3-compatible services:

### Supported Services:
- **MinIO** - Self-hosted object storage
- **DigitalOcean Spaces** - Simple cloud storage
- **Wasabi** - Hot cloud storage
- **Backblaze B2** - Cost-effective storage
- **Linode Object Storage**

### Setup Example (DigitalOcean Spaces):

1. **Create Space** in DigitalOcean
2. **Generate API keys** (Settings → API → Spaces Keys)
3. **In Dot Sync:**
   - Select: S3-Compatible
   - Endpoint: https://nyc3.digitaloceanspaces.com
   - Bucket: your-space-name
   - Region: nyc3
   - Access Key: DO...
   - Secret Key: ...

---

## 📊 **Comparison Matrix**

| Feature | iCloud | AWS S3 | Azure | GCP |
|---------|--------|--------|-------|-----|
| **Setup Time** | 30 sec | 5 min | 10 min | 10 min |
| **Credentials** | None | IAM keys | Service Principal | Service Account |
| **Free Tier** | 5GB | First year | 5GB/30 days | 5GB ongoing |
| **Cost (10MB)** | Free | ~$0.001/mo | ~$0.002/mo | ~$0.002/mo |
| **Multi-platform** | Mac only | ✅ All | ✅ All | ✅ All |
| **Complexity** | ⭐ Easy | ⭐⭐ Moderate | ⭐⭐⭐ Complex | ⭐⭐⭐ Complex |

---

## 🎯 **Recommendations**

### For Most Users:
**→ iCloud Drive** - Easiest setup, works great for Mac-to-Mac sync

### For Cross-Platform:
**→ AWS S3** - Most mature, well-documented, cheapest

### For Azure Users:
**→ Azure Blob** - Integrates with your existing Azure setup

### For Google Cloud Users:
**→ GCP Storage** - Integrates with your GCP environment

### For Privacy/Control:
**→ MinIO** - Self-hosted, complete control

---

## 🔒 **Security Best Practices**

### All Providers:
1. **Use IAM roles** (when possible) instead of long-term keys
2. **Enable versioning** - Keep history of changes
3. **Encrypt at rest** - Enable server-side encryption
4. **Use private buckets** - Never make dotfiles public
5. **Rotate credentials** - Change keys quarterly
6. **Enable MFA** - Protect your cloud account

### AWS S3 Specific:
```bash
# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-dotfiles-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-dotfiles-bucket \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access
aws s3api put-public-access-block \
  --bucket your-dotfiles-bucket \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

## 🧪 **Testing Your Setup**

### Quick Test:

1. **Enable Dry Run** mode (checkbox in main window)
2. **Select 1-2 non-critical files** (.aws_cheatsheet.md)
3. **Click "Preview Sync"**
4. **Review operations** - Should show upload
5. **Disable Dry Run**
6. **Click "Sync Selected"**
7. **Check cloud** - File should appear in bucket
8. **Delete local copy** of test file
9. **Sync again** - Should download from cloud
10. **Verify file restored**

### Full Test:
- Sync all files from Machine A
- Set up Machine B with same cloud storage
- Download all files on Machine B
- Modify a file on Machine B
- Sync from Machine B
- Sync on Machine A
- Should detect remote newer and offer to download

---

## ❗ **Important Notes**

### iCloud Limitations:
- **Mac only** - Can't use on Linux/Windows
- **Requires iCloud+** for more than 5GB
- **Sync delays** - May take minutes to propagate
- **Requires Full Disk Access** - Grant in System Settings

### AWS S3 Notes:
- **Region matters** - Use closest region for speed
- **Standard class** recommended - Instant retrieval
- **Versioning** highly recommended - Safety net

### Azure Notes:
- **Service principal** required - Can't use personal account directly
- **OAuth token** expires - Auto-refreshed
- **Storage account** must exist first

### GCP Notes:
- **Service account JSON** is sensitive - Store securely
- **Project ID** required
- **Bucket name** must be globally unique

---

## 💡 **Pro Tips**

### Use iCloud for:
- Personal Mac-to-Mac sync
- No technical setup desired
- Don't need cross-platform

### Use AWS S3 for:
- Multiple platforms (Mac + Linux + Windows)
- Team sharing (with IAM roles)
- Need versioning and history
- Want cheapest option

### Use Azure for:
- Already using Azure for other services
- Enterprise compliance requirements
- Need geo-redundancy

### Use GCP for:
- Already using Google Cloud
- Need Google's global network
- Want free 5GB tier

---

## 🎬 **Quick Start**

**Fastest path to syncing:**

1. **Choose iCloud** (if Mac-only)
2. **Open Preferences** (⌘,)
3. **Cloud Storage** tab → Select iCloud Drive
4. **Save**
5. **Select files** in main window
6. **Click "Sync Selected"**
7. **Done!** Files are syncing via iCloud

**On second Mac:**
1. **Install Dot Sync**
2. **Configure iCloud** (same as above)
3. **Click "Scan"** - Detects remote files
4. **Select files** to download
5. **Click "Sync Selected"**
6. **Your configs are now synced!**

---

## 📞 **Support**

**Issues?**
- Check credentials are correct
- Verify bucket/container exists
- Test connection in Preferences
- Review Console.app for errors
- Open issue: https://github.com/kochj23/DotSync/issues

**Questions about cloud providers?**
- AWS: https://docs.aws.amazon.com/s3/
- Azure: https://docs.microsoft.com/azure/storage/blobs/
- GCP: https://cloud.google.com/storage/docs
- iCloud: https://developer.apple.com/icloud/

---

**Author:** Jordan Koch
**Repository:** https://github.com/kochj23/DotSync
