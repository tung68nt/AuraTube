#!/bin/bash
clear
echo "============================================================"
echo "          AuraTube macOS - Mở Khóa Cài Đặt (Gatekeeper)     "
echo "============================================================"
echo ""
echo "Nếu mở AuraTube bị báo lỗi 'App bị hỏng' hoặc không cho mở,"
echo "bạn chỉ cần chạy lệnh này để cấp quyền mở ứng dụng."
echo ""

APP_FOUND=false

# 1. Tự động xử lý nếu app đã được kéo vào /Applications
if [ -d "/Applications/AuraTube.app" ]; then
    echo "🔍 Phát hiện AuraTube đã có trong thư mục /Applications."
    xattr -cr "/Applications/AuraTube.app" 2>/dev/null
    echo "✅ Đã tự động mở khóa thành công cho /Applications/AuraTube.app!"
    echo "🎉 Giờ bạn có thể mở AuraTube trong Launchpad hoặc Applications."
    echo "------------------------------------------------------------"
    APP_FOUND=true
fi

# 2. Mở sẵn lệnh xattr -cr để kéo app vào
echo "👉 Hoặc KÉO AuraTube.app VÀO ĐÂY rồi nhấn phím ENTER:"
read -e -p "xattr -cr " TARGET_PATH

if [ -n "$TARGET_PATH" ]; then
    # Làm sạch dấu nháy và ký tự thoát do kéo thả từ Finder
    CLEAN_PATH=$(eval echo "$TARGET_PATH" 2>/dev/null || echo "$TARGET_PATH")
    CLEAN_PATH="${CLEAN_PATH%\'}"
    CLEAN_PATH="${CLEAN_PATH#\'}"
    CLEAN_PATH="${CLEAN_PATH%\"}"
    CLEAN_PATH="${CLEAN_PATH#\"}"
    
    if [ -d "$CLEAN_PATH" ]; then
        xattr -cr "$CLEAN_PATH"
        echo ""
        echo "✅ Đã mở khóa thành công cho: $CLEAN_PATH"
        echo "🎉 Bạn có thể mở AuraTube bình thường!"
    else
        echo ""
        echo "⚠️ Không tìm thấy đường dẫn: $CLEAN_PATH"
    fi
elif [ "$APP_FOUND" = true ]; then
    echo ""
    echo "Đã hoàn tất mở khóa AuraTube."
fi

echo ""
read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng cửa sổ..."
echo ""
