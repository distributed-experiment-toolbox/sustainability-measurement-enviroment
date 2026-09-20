#!/bin/bash
# Create a cloudinit iso for debian installs on any linux/osx installation
# Usage: ./mkiso.sh /path/to/public_key.pub [output.iso] [hostname]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_ISO="${2:-debian-cloudinit.iso}"
PUBLIC_KEY_FILE="${1:?Error: Public key file path required. Usage: $0 /path/to/public_key.pub [output.iso]}"
HOSTNAME="${3:-debian-qemu}"

if [[ -z "${HOSTNAME// }" ]]; then
    echo -e "${RED}Error: Hostname cannot be empty${NC}" >&2
    exit 1
fi

# Validate inputs
if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
    echo -e "${RED}Error: Public key file not found: $PUBLIC_KEY_FILE${NC}" >&2
    exit 1
fi

if [[ ! "$PUBLIC_KEY_FILE" =~ \.pub$ ]]; then
    echo -e "${YELLOW}Warning: Public key file should have .pub extension${NC}" >&2
fi


# Check for required tools
check_command() {
  if ! command -v "$1" &> /dev/null; then
    return 1
  fi
  return 0
}

echo -e "${YELLOW}Checking for required tools...${NC}"
if ! check_command "mkisofs"; then
  echo -e "${RED}Error: mkisofs is not installed${NC}" >&2
  exit 1
fi

HAVE_CLOUD_LOCALDS=false
if check_command "cloud-localds"; then
  HAVE_CLOUD_LOCALDS=true
fi
# Create temporary directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo -e "${GREEN}Creating cloud-init configuration...${NC}"

# Read the public key
PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")

# Create meta-data file for cloud-localds
cat > "$TMPDIR/meta-data" <<EOF
instance-id: ${HOSTNAME}-01
local-hostname: ${HOSTNAME}
EOF

# Create user-data file with cloud-init configuration
cat > "$TMPDIR/user-data" <<'CLOUD_INIT_EOF'
#cloud-config
packages:
  - qemu-guest-agent
  - sudo
  - python3.11
  - python3.11-venv

package_update: true
package_upgrade: true

users:
  - name: debian
    gecos: Debian User
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - DEBIAN_PUBLIC_KEY_PLACEHOLDER

ssh_authorized_keys:
  - ROOT_PUBLIC_KEY_PLACEHOLDER

runcmd:
  - systemctl start qemu-guest-agent
  - systemctl enable qemu-guest-agent
CLOUD_INIT_EOF

# Replace placeholders with actual public key
sed -i.bak "s|DEBIAN_PUBLIC_KEY_PLACEHOLDER|$PUBLIC_KEY|g" "$TMPDIR/user-data"
sed -i.bak "s|ROOT_PUBLIC_KEY_PLACEHOLDER|$PUBLIC_KEY|g" "$TMPDIR/user-data"
rm -f "$TMPDIR/user-data.bak"


# Generate the ISO
echo -e "${GREEN}Generating ISO: $OUTPUT_ISO${NC}"

if [[ "$HAVE_CLOUD_LOCALDS" == "true" ]]; then
  # Use cloud-localds if available (Linux)
  cloud-localds "$OUTPUT_ISO" "$TMPDIR/user-data" "$TMPDIR/meta-data"
else
  # Fallback: manually create ISO with mkisofs (works on macOS and Linux)
  # Create the cloud-init directory structure
  ISO_CONTENT="$TMPDIR/iso_content"
  mkdir -p "$ISO_CONTENT"
  cp "$TMPDIR/user-data" "$ISO_CONTENT/"
  cp "$TMPDIR/meta-data" "$ISO_CONTENT/"
    
  # Create the ISO with cloud-init structure
  mkisofs -output "$OUTPUT_ISO" -volid "cidata" -joliet -rock "$ISO_CONTENT" 2>/dev/null || \
  mkisofs -o "$OUTPUT_ISO" -V "cidata" -J -R "$ISO_CONTENT" 2>/dev/null
fi
echo -e "${GREEN}Success! ISO created: $OUTPUT_ISO${NC}"
echo -e "${YELLOW}You can now use this ISO with QEMU:${NC}"
echo "  qemu-system-x86_64 -cdrom $OUTPUT_ISO ..."

