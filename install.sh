#!/bin/bash

# Function to prompt for input
prompt_for_input() {
    read -p "$1: " input
    echo $input
}

# Update and install necessary software
sudo apt update
sudo apt install -y curl git speedtest-cli

# Clone the GitHub repository
git clone https://github.com/yourusername/network_speed_test.git /root/network_speed_test

# Change directory to the cloned repository
cd /root/network_speed_test

# Prompt user for Telegram Bot Token and Chat ID
TELEGRAM_BOT_TOKEN=$(prompt_for_input "Enter your Telegram Bot Token")
TELEGRAM_CHAT_ID=$(prompt_for_input "Enter your Telegram Chat ID")

# Create network_speed_test.sh with user inputs
cat <<EOL > /root/network_speed_test/network_speed_test.sh
#!/bin/bash

# 配置部分
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
TEST_INTERVAL=\$((4 * 3600))  # 测试的间隔时间，4小时
TEST_DURATION=20  # 网络测速的持续时间，单位是秒
BANDWIDTH_LIMIT="20mbit"  # 限制带宽为20Mbps
LOCK_FILE="/tmp/network_speed_test.lock"

# 锁定机制
exec 200>\$LOCK_FILE
flock -n 200 || exit 1

# 执行网络测速并限制带宽
perform_speed_test() {
    # 设置限速
    sudo tc qdisc add dev eth0 root tbf rate \$BANDWIDTH_LIMIT burst 32kbit latency 400ms
    result=\$(speedtest-cli --simple --timeout \$TEST_DURATION)
    # 移除限速
    sudo tc qdisc del dev eth0 root
    echo "\$result"
}

# 发送通知到Telegram
send_to_telegram() {
    local message="\$1"
    curl -s -X POST "https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="\$TELEGRAM_CHAT_ID" \
        -d text="\$message"
}

# 计算流量消耗
calculate_traffic() {
    local download_speed=\$(echo "\$1" | awk '/Download/{print \$2}')
    local upload_speed=\$(echo "\$1" | awk '/Upload/{print \$2}')
    local duration=\$2
    local downloaded=\$(echo "\$download_speed \$duration" | awk '{print \$1 * \$2 / 8 / 1024}')
    local uploaded=\$(echo "\$upload_speed \$duration" | awk '{print \$1 * \$2 / 8 / 1024}')
    echo "\$downloaded \$uploaded"
}

# 主函数
main() {
    local start_time=\$(date +"%Y-%m-%d %H:%M:%S")
    local result=\$(perform_speed_test)
    local end_time=\$(date +"%Y-%m-%d %H:%M:%S")
    local traffic=\$(calculate_traffic "\$result" \$TEST_DURATION)
    local downloaded=\$(echo "\$traffic" | awk '{print \$1}')
    local uploaded=\$(echo "\$traffic" | awk '{print \$2}')
    local message="网络测速结果:\\n执行时间: \$start_time，持续时间: \${TEST_DURATION}秒\\n\$result\\nDownloaded: \${downloaded} MB, Uploaded: \${uploaded} MB"
    send_to_telegram "\$message"
}

main
EOL

# Ensure the script has execution permissions
chmod +x /root/network_speed_test/network_speed_test.sh

# Configure cron job
(crontab -l 2>/dev/null; echo "0 */4 * * * /root/network_speed_test/network_speed_test.sh") | crontab -

echo "Installation complete. The network speed test will run every 4 hours."
