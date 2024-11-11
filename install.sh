#!/bin/bash

# Function to display error messages
error_exit() {
    echo "$1" >&2
    exit 1
}

# Function to prompt for user confirmation
confirm() {
    read -r -p "${1:-Are you sure?} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# Function to select PHP version
select_php_version() {
    echo "Available PHP versions:"
    echo "1) PHP 7.4"
    echo "2) PHP 8.0"
    echo "3) PHP 8.1"
    echo "4) PHP 8.2"
    echo "5) PHP 8.3"
    echo "6) PHP 8.4"
    read -p "Select PHP version (1-6): " php_choice
    
    case $php_choice in
        1) PHP_VERSION="7.4" ;;
        2) PHP_VERSION="8.0" ;;
        3) PHP_VERSION="8.1" ;;
        4) PHP_VERSION="8.2" ;;
        5) PHP_VERSION="8.3" ;;
        6) PHP_VERSION="8.4" ;;
        *) error_exit "Invalid PHP version selected" ;;
    esac
    echo "Selected PHP version: $PHP_VERSION"
}

# Function to prompt for MySQL credentials
get_mysql_credentials() {
    read -p "Enter MySQL username (default: admin): " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-admin}
    
    read -s -p "Enter MySQL password: " MYSQL_PASS
    echo
    
    read -p "Enter database name (default: mydatabase): " DB_NAME
    DB_NAME=${DB_NAME:-mydatabase}
}

# Update system
echo "Updating system packages..."
sudo apt update || error_exit "Failed to update system packages"

# Install Apache
echo "Installing Apache2..."
sudo apt install -y apache2 || error_exit "Failed to install Apache2"

# Add PHP repository and install PHP
echo "Setting up PHP repository..."
sudo apt install -y ca-certificates apt-transport-https software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update

# Select PHP version
select_php_version

# Install PHP and extensions
echo "Installing PHP ${PHP_VERSION} and extensions..."
sudo apt install -y php${PHP_VERSION} \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-opcache \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-json \
    php${PHP_VERSION}-readline \
    php${PHP_VERSION}-soap \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-imagick \
    php${PHP_VERSION}-ldap || error_exit "Failed to install PHP"

# Install MySQL
echo "Installing MySQL server..."
sudo apt install -y mysql-server || error_exit "Failed to install MySQL"

# Get MySQL credentials
get_mysql_credentials

# Configure MySQL
echo "Configuring MySQL..."
sudo mysql -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASS}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'localhost' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"
sudo mysql -e "CREATE DATABASE ${DB_NAME};"

# Install Git
echo "Installing Git..."
sudo apt install -y git || error_exit "Failed to install Git"

# Install Composer
echo "Installing Composer..."
cd ~
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
HASH=$(curl -sS https://composer.github.io/installer.sig)
php -r "if (hash_file('SHA384', '/tmp/composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
sudo php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer

# Function to select Node.js version
select_node_version() {
    echo "Available Node.js versions:"
    echo "1) Node.js 16.x (LTS)"
    echo "2) Node.js 18.x (LTS)"
    echo "3) Node.js 20.x (Current)"
    read -p "Select Node.js version (1-3): " node_choice
    
    case $node_choice in
        1) NODE_VERSION="16" ;;
        2) NODE_VERSION="18" ;;
        3) NODE_VERSION="20" ;;
        *) error_exit "Invalid Node.js version selected" ;;
    esac
    echo "Selected Node.js version: $NODE_VERSION"
}

# Install Node.js
echo "Installing Node.js..."
select_node_version
cd ~
curl -sL https://deb.nodesource.com/setup_${NODE_VERSION}.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install -y nodejs

# Install Yarn (optional)
if confirm "Do you want to install Yarn?"; then
    echo "Installing Yarn..."
    npm install --global yarn
fi

# Install PM2 (optional)
if confirm "Do you want to install PM2?"; then
    echo "Installing PM2..."
    sudo npm install --global pm2
fi

# Get project details
read -p "Enter GitHub repository URL: " REPO_URL

# Navigate to web root
cd /var/www/html

# Clone the repository
echo "Cloning repository..."
sudo git clone "$REPO_URL" || error_exit "Failed to clone repository"

# Get the repository name from URL and cd into it
REPO_NAME=$(basename "$REPO_URL" .git)
cd "$REPO_NAME"

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html/"$REPO_NAME"
sudo chmod -R 755 /var/www/html/"$REPO_NAME"

# Install dependencies with Composer
echo "Installing Composer dependencies..."
sudo -u www-data composer install || error_exit "Failed to install Composer dependencies"

# Setup environment file
echo "Setting up environment file..."
sudo cp .env.example .env || error_exit "Failed to create .env file"

# Generate application key
sudo php artisan key:generate || error_exit "Failed to generate application key"

# Update database credentials in .env
sudo sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
sudo sed -i "s/DB_USERNAME=.*/DB_USERNAME=${MYSQL_USER}/" .env
sudo sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_PASS}/" .env

# Get domain name
read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME

# Create Apache configuration file
echo "Creating Apache configuration..."
sudo tee /etc/apache2/sites-available/${DOMAIN_NAME}.conf << EOF
<VirtualHost *:80>
    ServerAdmin admin@${DOMAIN_NAME}
    ServerName ${DOMAIN_NAME}
    DocumentRoot /var/www/html/${REPO_NAME}/public

    <Directory /var/www/html/${REPO_NAME}/public>
        Options Indexes MultiViews FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Enable Apache rewrite module
sudo a2enmod rewrite

# Enable the new site
sudo a2ensite ${DOMAIN_NAME}.conf

# Disable default site
sudo a2dissite 000-default.conf

# Restart Apache
sudo systemctl restart apache2

# SSL Installation (optional)
if confirm "Do you want to install SSL certificate?"; then
    echo "WARNING: Before proceeding, ensure your domain's DNS A record points to this server's IP address."
    if confirm "Have you configured the DNS settings?"; then
        echo "Installing Certbot..."
        sudo apt install -y certbot python3-certbot-apache
        echo "Generating SSL certificate..."
        sudo certbot --apache
    else
        echo "Please configure DNS settings first and run SSL installation later."
    fi
fi

echo "Installation complete!"
echo "PHP Version: ${PHP_VERSION}"
echo "Node.js Version: ${NODE_VERSION}"
echo "MySQL User: ${MYSQL_USER}"
echo "Database Name: ${DB_NAME}"
