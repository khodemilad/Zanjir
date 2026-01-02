#!/bin/bash
# زنجیر⛓️ - اسکریپت نصب خودکار
# پیام‌رسان امن و غیرمتمرکز ایرانی‌شده بر پایه Matrix
# پشتیبانی از دامنه و IP خالی
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║           ⛓️  زنجیر - نصب‌کننده خودکار ⛓️            ║"
    echo "║      پیام‌رسان امن و غیرمتمرکز بر پایه Matrix      ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${BLUE}[اطلاعات]${NC} $1"; }
log_success() { echo -e "${GREEN}[موفق]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[هشدار]${NC} $1"; }
log_error() { echo -e "${RED}[خطا]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "لطفاً با دسترسی root اجرا کنید: sudo ./install.sh"
        exit 1
    fi
}

# Check if input is an IP address
is_ip_address() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_address() {
    if [ -z "$1" ]; then
        echo ""
        log_error "آدرس مشخص نشده است!"
        echo -e "استفاده: ${YELLOW}sudo ./install.sh yourdomain.com${NC}"
        echo -e "   یا:  ${YELLOW}sudo ./install.sh YOUR_IP_ADDRESS${NC}"
        exit 1
    fi
    
    SERVER_ADDRESS="$1"
    
    if is_ip_address "$SERVER_ADDRESS"; then
        IP_MODE=true
        log_warning "حالت IP تشخیص داده شد: $SERVER_ADDRESS"
        log_warning "⚠️  توجه: بدون SSL اجرا خواهد شد (فقط HTTP)"
        PROTOCOL="http"
    else
        IP_MODE=false
        log_info "دامنه: $SERVER_ADDRESS"
        PROTOCOL="https"
    fi
}

install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker قبلاً نصب شده است."
        return
    fi
    log_info "در حال نصب Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_success "Docker با موفقیت نصب شد."
}

install_docker_compose() {
    if command -v docker compose &> /dev/null || command -v docker-compose &> /dev/null; then
        log_success "Docker Compose قبلاً نصب شده است."
        return
    fi
    log_info "در حال نصب Docker Compose..."
    apt-get update && apt-get install -y docker-compose-plugin
    log_success "Docker Compose با موفقیت نصب شد."
}

generate_secrets() {
    log_info "تولید رمزهای امنیتی..."
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
    REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
    log_success "رمزها تولید شدند."
}

create_env_file() {
    log_info "ایجاد فایل .env..."
    cat > .env <<EOF
# Server Configuration
DOMAIN=${SERVER_ADDRESS}
SERVER_ADDRESS=${SERVER_ADDRESS}
PROTOCOL=${PROTOCOL}
IP_MODE=${IP_MODE}

# Dendrite Configuration
REGISTRATION_SHARED_SECRET=${REGISTRATION_SECRET}

# PostgreSQL Configuration
POSTGRES_USER=dendrite
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=dendrite

# Let's Encrypt Email (only for domain mode)
LETSENCRYPT_EMAIL=admin@${SERVER_ADDRESS}
EOF
    chmod 600 .env
    log_success "فایل .env ایجاد شد."
}

setup_caddyfile() {
    log_info "تنظیم Caddyfile..."
    
    if [ "$IP_MODE" = true ]; then
        # Use IP mode Caddyfile (HTTP only)
        cp Caddyfile.ip-mode Caddyfile.active
        log_warning "از حالت HTTP (بدون SSL) استفاده می‌شود."
    else
        # Use domain mode Caddyfile (HTTPS)
        cp Caddyfile Caddyfile.active
        log_success "از حالت HTTPS با Let's Encrypt استفاده می‌شود."
    fi
}

update_configs() {
    log_info "به‌روزرسانی فایل‌های تنظیمات..."
    
    # Update element-config.json
    if [ "$IP_MODE" = true ]; then
        sed -i "s|https://\${DOMAIN}|http://${SERVER_ADDRESS}|g" config/element-config.json
    else
        sed -i "s|\${DOMAIN}|${SERVER_ADDRESS}|g" config/element-config.json
    fi
    
    # Update dendrite.yaml
    sed -i "s/\${DOMAIN}/${SERVER_ADDRESS}/g" dendrite/dendrite.yaml
    sed -i "s/\${POSTGRES_USER}/dendrite/g" dendrite/dendrite.yaml
    sed -i "s/\${POSTGRES_PASSWORD}/${POSTGRES_PASSWORD}/g" dendrite/dendrite.yaml
    sed -i "s/\${POSTGRES_DB}/dendrite/g" dendrite/dendrite.yaml
    sed -i "s/\${REGISTRATION_SHARED_SECRET}/${REGISTRATION_SECRET}/g" dendrite/dendrite.yaml
    
    # Update well_known URLs for IP mode
    if [ "$IP_MODE" = true ]; then
        sed -i "s|:443|:80|g" dendrite/dendrite.yaml
        sed -i "s|https://|http://|g" dendrite/dendrite.yaml
    fi
    
    log_success "تنظیمات به‌روز شدند."
}

generate_matrix_key() {
    log_info "تولید کلید امضای Matrix..."
    if [ ! -f "dendrite/matrix_key.pem" ]; then
        docker run --rm -v "$(pwd)/dendrite:/etc/dendrite" \
            matrixdotorg/dendrite-monolith:latest \
            /usr/bin/generate-keys --private-key /etc/dendrite/matrix_key.pem
        chmod 600 dendrite/matrix_key.pem
        log_success "کلید Matrix تولید شد."
    else
        log_warning "کلید Matrix قبلاً وجود دارد."
    fi
}

update_docker_compose() {
    log_info "تنظیم docker-compose برای حالت فعلی..."
    
    # Update Caddyfile path in docker-compose
    sed -i "s|./Caddyfile:/etc/caddy/Caddyfile|./Caddyfile.active:/etc/caddy/Caddyfile|g" docker-compose.yml
    
    log_success "docker-compose به‌روز شد."
}

start_services() {
    log_info "راه‌اندازی سرویس‌ها..."
    
    # Run element-copy first to prepare files
    docker compose run --rm element-copy
    
    # Start all services
    docker compose up -d postgres dendrite element caddy
    
    log_success "سرویس‌ها راه‌اندازی شدند!"
}

print_success() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ✅ نصب با موفقیت انجام شد! ✅            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "🌐 آدرس وب: ${BLUE}${PROTOCOL}://${SERVER_ADDRESS}${NC}"
    
    if [ "$IP_MODE" = true ]; then
        echo ""
        echo -e "${YELLOW}⚠️  هشدار: در حال اجرا بدون SSL (HTTP)${NC}"
        echo -e "${YELLOW}   این حالت فقط برای تست مناسب است!${NC}"
    fi
    
    echo ""
    echo -e "📝 برای ثبت‌نام کاربر جدید از دستور زیر استفاده کنید:"
    echo -e "${YELLOW}docker exec -it zanjir-dendrite /usr/bin/create-account \\
    --config /etc/dendrite/dendrite.yaml \\
    --username YOUR_USERNAME \\
    --admin${NC}"
    echo ""
    echo -e "🔑 رمز ثبت‌نام: ${YELLOW}${REGISTRATION_SECRET}${NC}"
    echo ""
    log_info "این اطلاعات در فایل .env ذخیره شده‌اند."
}

# Main
print_banner
check_root
check_address "$1"
install_docker
install_docker_compose
generate_secrets
create_env_file
setup_caddyfile
update_configs
generate_matrix_key
update_docker_compose
start_services
print_success
