---
title: How to Upload Custom Images
description: Upload custom images to a DigitalOcean account to create Droplets based on them.
product: Custom Images
url: https://docs.digitalocean.com/products/custom-images/how-to/upload/
last_updated: "2026-07-13"
---

> **For AI agents:** The documentation index is at [https://docs.digitalocean.com/llms.txt](https://docs.digitalocean.com/llms.txt). Markdown versions of pages use the same URL with `index.html.md` in place of the HTML page (for example, append `index.html.md` to the directory path instead of opening the HTML document).

# How to Upload Custom Images

Custom images are Linux and Unix-like images you import to DigitalOcean. You can create Droplets based custom images, which lets you migrate and scale your workloads without spending time recreating your environment from scratch.

## Image Requirements

Images you upload to DigitalOcean must meet the following requirements:

- **Operating system**. Images must have a Unix-like OS.
- **File format**. Images must be in one of the following file formats:

  - [Raw (`.img`)](https://en.wikipedia.org/wiki/IMG_%28file_format%29) with an MBR or GPT partition table
  - qcow2
  - [VHDX](https://en.wikipedia.org/wiki/VHD_%28file_format%29#Virtual_Hard_Disk_%28VHDX%29)
  - VDI
  - VMDK
- **Size**. Images must be 100 GB or less when uncompressed, including the filesystem.
- **Filesystem**. Images must support the ext3 or ext4 filesystems.
- **`cloud-init`** . Images must have cloud-init 0.7.7 or higher, cloudbase-init, coreos-cloudinit, ignition, or bsd-cloudinit installed and configured correctly. If your image's default `cloud-init` configuration lists the `NoCloud` data source before the `ConfigDrive` data source, Droplets created from your image will not function properly.

  ## Click here to display detailed cloud-init instructions.

  If your image's default `cloud-init` configuration lists the `NoCloud` data source before the `ConfigDrive` data source, Droplets created from your image will not function properly. We have detailed instructions on [reconfiguring `cloud-init` for Ubuntu 18.04](https://www.digitalocean.com/community/tutorials/how-to-create-a-digitalocean-droplet-from-an-ubuntu-iso-format-image#step-3-%E2%80%94-reconfiguring-cloud-init).

  The process for fixing this in general is to edit the `cloud-init` config file either using a text editor or with `dpkg-reconfigure` to order the data sources correctly. The actual line in the file should look similar to this when you're done:

  ```
  datasource_list: [ ConfigDrive, OpenNebula, DigitalOcean, Azure, AltCloud, OVF, MAAS, GCE, OpenStack, CloudSigma, SmartOS, None, NoCloud ]
  ```

  After you edit the file, you need to purge the previous `cloud-init` data so `cloud-init` runs using the proper data source when your Droplet boots. You can do this using `cloud-init clean` or by manually cleaning out `/var/lib/cloud`. You should also verify the networking configuration, the details of which vary by distribution.
- **SSH configuration**. Images must have `sshd` installed and configured to run on boot. If your image does not have `sshd` set up, you will not have SSH access to Droplets created from that image unless you [recover access using the Recovery Console](https://docs.digitalocean.com/products/droplets/how-to/recovery/recovery-console/index.html.md).

You can also upload a custom image that meets the above criteria as a compressed [gzip](https://en.wikipedia.org/wiki/Gzip) or [bzip2](https://en.wikipedia.org/wiki/Bzip2) file.

**Warning**:

  You must add an SSH key when creating Droplets from a custom image. These Droplets have password authentication disabled by default and you cannot use the control panel to reset the root password.

You can find [cloud-friendly official Unix-like OS images on OpenStack](https://docs.openstack.org/image-guide/obtain-images.html).

## Upload a Custom Image using Automation

## How to Upload a Custom Image Using the DigitalOcean CLI

1. [Install `doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/index.html.md), the official DigitalOcean CLI.
2. [Create a personal access token](https://docs.digitalocean.com/reference/api/create-personal-access-token/index.html.md) and save it for use with `doctl`.
3. Use the token to grant `doctl` access to your DigitalOcean account.

   ```shell
   doctl auth init
   ```
4. Finally, run `doctl compute image create`. Basic usage looks like this, but you can [read the usage docs](https://docs.digitalocean.com/reference/doctl/reference/compute/image/create/index.html.md) for more details:

   ```shell
   doctl compute image create <image-name> [flags]
   ```

   The following example creates a custom image named `Example Image` from a URL and stores it in the `nyc1` region:

   ```shell
   doctl compute image create "Example Image" --image-url "https://example.com/image.img" --region nyc1
   ```

## How to Upload a Custom Image Using the DigitalOcean API

[Create a personal access token](https://docs.digitalocean.com/reference/api/create-personal-access-token/index.html.md) and save it for use with the API.

### cURL

Send a POST request to [`https://api.digitalocean.com/v2/images`](https://docs.digitalocean.com/reference/api/reference/images/index.html.md#images_create_custom).

Using cURL:

```shell
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
  -d '{"name": "ubuntu-18.04-minimal", "url": "http://cloud-images.ubuntu.com/minimal/releases/bionic/release/ubuntu-18.04-minimal-cloudimg-amd64.img", "distribution": "Ubuntu", "region": "nyc3", "description": "Cloud-optimized image w/ small footprint", "tags":["base-image", "prod"]}' \
  "https://api.digitalocean.com/v2/images"
```

### Python

Using [PyDo](https://github.com/digitalocean/pydo), the official DigitalOcean API client for Python:

```python
import os
from pydo import Client

client = Client(token=os.environ.get("DIGITALOCEAN_TOKEN"))

req = {
  "name": "ubuntu-18.04-minimal",
  "url": "http://cloud-images.ubuntu.com/minimal/releases/bionic/release/ubuntu-18.04-minimal-cloudimg-amd64.img",
  "distribution": "Ubuntu",
  "region": "nyc3",
  "description": "Cloud-optimized image w/ small footprint",
  "tags": [
    "base-image",
    "prod"
  ]
}

resp = client.images.create_custom(body=req)
```

## Upload a Custom Image using the Control Panel

To upload an image via the [control panel](https://cloud.digitalocean.com), in the left menu, click **Backups & Snapshots**, then click the **Custom Images** tab.

![Custom Images page listing uploaded images with image details, and a More dropdown menu for starting a Droplet or deleting the image.](https://docs.digitalocean.com/screenshots/custom-images/overview.c7f454638be3817115f1c638d877b59ed3cd004f20fa6401d8193ad4a0b3ffa6.png)

Here, you can upload a custom image in two ways:

- You can upload an image file directly by clicking the **Upload Image** button, which opens a file selector, or by dragging and dropping the image file into the window.

  **Note**:

    Some browsers have file size limitations. If you're unable to upload a large file via your browser, you can host the file somewhere and upload it by URL. For example, you can upload your image to [Spaces](https://docs.digitalocean.com/products/spaces/index.html.md) and [make the file public](https://docs.digitalocean.com/products/spaces/how-to/set-file-permissions/index.html.md) or use a file sharing tool like [Dropbox](https://www.dropbox.com). Make sure the URL ends in the file extension (like `example.com/file.raw` instead of `example.com/file.raw?dl=0`).
- You can enter the URL to an image file by clicking the **Import via URL** button. In the **Upload an Image** window that opens, enter the URL of the image you want to use in the text field, then click **Next**. The control panel supports uploads from HTTP, HTTPS, and FTP URLs.

  **Note**:

    Importing a custom image by URL fails if the image is served by a CDN that doesn't support HEAD requests. If you have trouble importing an image via a URL, try downloading the file and uploading it directly.

Using either upload method, the next window that opens prompts you to enter details about your image.

- **Edit Image Name**: This field is pre-filled with the name of the file you uploaded, but you can customize it if you like.
- **Distribution**: You can choose from Arch Linux, Fedora, Ubuntu, CentOS, Debian, or Unknown.
- **Choose a datacenter region**: Your image is located in a single datacenter of your choice at first, and you can [transfer custom images to different datacenters](https://docs.digitalocean.com/products/custom-images/how-to/add-regions/index.html.md) after uploading.
- **Tags** (optional): Custom images support [tagging](https://docs.digitalocean.com/products/droplets/how-to/tag/index.html.md). You can add tags to your custom image here or at any time after uploading.
- **Notes** (optional): This is a plain text field you can use to enter any additional notes about your custom image for your use.

After you've entered these details, click **Upload Image**. A progress bar appears on the control panel next to the **Upload Image** button. If you click **Details** above this progress bar, a window appears listing all of your current uploads.

You can click the **X** next to any in-progress upload to cancel it, or click **Cancel Uploads** to cancel all current uploads.

Once you have at least one custom image added to your account, you can [create a Droplet from a custom image](https://docs.digitalocean.com/products/custom-images/how-to/create-droplets/index.html.md).
