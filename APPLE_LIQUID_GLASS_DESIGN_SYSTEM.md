#  Apple Liquid Glass Design System (ALG-DS)
> **Phiên bản:** 1.0.0 • **Nền tảng:** Universal (Web / Next.js / React / macOS / iOS / Electron)  
> **Ngôn ngữ phong cách:** Sophisticated Glassmorphism • macOS Sonoma/Sequoia HIG • visionOS Materials

---

## Mục Lục
1. [Triết Lý Cốt Lõi & Định Luật Vật Lý Quang Học](#1-triết-lý-cốt-lõi--định-luật-vật-lý-quang-học)
2. [Hệ Thống Foundation Tokens (Nền Tảng)](#2-hệ-thống-foundation-tokens-nền-tảng)
   - [2.1. Bảng màu & Độ đục Kính (Glass Materials)](#21-bảng-màu--độ-đục-kính-glass-materials)
   - [2.2. Phản xạ Viền Quang Học (Specular Rim Lighting)](#22-phản-xạ-viền-quang-học-specular-rim-lighting)
   - [2.3. Chiều Sâu & Bóng Đổ Vật Lý (Depth & Elevation)](#23-chiều-sâu--bóng-đổ-vật-lý-depth--elevation)
   - [2.4. Đường Cong Squircle (Continuous Curvature)](#24-đường-cong-squircle-continuous-curvature)
   - [2.5. Typography & Phân Cấp Văn Bản](#25-typography--phân-cấp-văn-bản)
3. [Thư Viện Component Chuẩn (Component Specifications)](#3-thư-viện-component-chuẩn-component-specifications)
   - [3.1. Modal / Sheet / Alert (Hộp thoại & Popup)](#31-modal--sheet--alert-hộp-thoại--popup)
   - [3.2. Action Buttons & Controls (Nút bấm & Bộ điều khiển)](#32-action-buttons--controls-nút-bấm--bộ-điều-khiển)
   - [3.3. Recessed Plates (Đĩa kính khảm chìm)](#33-recessed-plates-đĩa-kính-khảm-chìm)
   - [3.4. Search Bar & Form Inputs (Ô tìm kiếm & Nhập liệu)](#34-search-bar--form-inputs-ô-tìm-kiếm--nhập-liệu)
   - [3.5. Floating Header & Island Toast (Thanh điều hướng nổi & Toast)](#35-floating-header--island-toast-thanh-điều-hướng-nổi--toast)
4. [Triển Khai Web (Tailwind CSS / Next.js / CSS Variables)](#4-triển-khai-web-tailwind-css--nextjs--css-variables)
5. [Triển Khai Native macOS / iOS (SwiftUI)](#5-triển-khai-native-macos--ios-swiftui)
6. [Tiêu Chuẩn Accessibility & Chế Độ Giảm Trong Suốt](#6-tiêu-chuẩn-accessibility--chế-độ-giảm-trong-suốt)
7. [Checklist Phê Duyệt Thiết Kế (Design Review Checklist)](#7-checklist-phê-duyệt-thiết-kế-design-review-checklist)

---

## 1. Triết Lý Cốt Lõi & Định Luật Vật Lý Quang Học

Apple Liquid Glass không đơn thuần là thuộc tính `backdrop-filter: blur()`. Nó là sự mô phỏng **thấu kính khúc xạ quang học đa tầng (Multi-layer Optical Refraction)** trong tự nhiên:

```
┌────────────────────────────────────────────────────────┐  ← Mép trên: Specular Rim Highlight (Trắng sáng 0.75pt)
│ ░░░░░░░░░░░ Ambient Top Sheen (Ánh sáng trần dội xuống)░░│
│                                                        │
│     [ App Icon ]    Tiêu Đề Hộp Thoại (Bold 16pt)      │
│     (Squircle 14)   Phụ đề thông tin (12.5pt)          │
│                                                        │
│   ┌──────────────────────────────────────────────────┐ │
│   │ ░░░ Recessed Frosted Plate (Kính khảm chìm 4%) ░░│ │  ← Vùng nội dung cuộn (không lồng hộp cứng)
│   └──────────────────────────────────────────────────┘ │
│                                                        │
│   [ ] Tùy chọn hệ thống          [Để sau] [Hành động]  │  ← Góc phải: Cụm nút bấm chuẩn công thái học
└────────────────────────────────────────────────────────┘  ← Mép dưới: Specular Lowlight (Tối dịu)
  ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼
  Physical Ambient Drop Shadow (Bóng đổ vật lý mềm, không màu neon)
```

### 3 Nguyên Tắc Bất Di Bất Dịch:
1. **Không Dùng Màu Đặc Giả Kính (Avoid Faux-Glass):** Màu nền tuyệt đối không vượt quá **75% opacity**. Nếu đặt nền `#1e2026` đục ngầu 95%, bản chất đã là một mảng nhựa/gỗ tối màu chứ không còn là kính quang học.
2. **Nguồn Sáng Đỉnh Đầu (Top-Down Key Light):** Viền kính và bề mặt luôn có xu hướng sáng hơn ở đỉnh và tối dịu dần về phía đáy.
3. **Bài Trừ Triệt Để "AI Vibe Code":**
   - ❌ Không dùng quầng sáng blur neon lòe loẹt phía sau icon (`blur(16px)` màu đỏ/tím).
   - ❌ Không dùng nút tròn "X" trôi nổi góc trên của Sheet.
   - ❌ Không dùng bóng đổ xanh neon rực mắt dưới nút bấm chính.
   - ❌ Không ngắt dòng chữ vô lý trên nút bấm (như "Để \n sau").

---

## 2. Hệ Thống Foundation Tokens (Nền Tảng)

### 2.1. Bảng màu & Độ đục Kính (Glass Materials)

Mỗi lớp kính gồm 2 thành tố hòa trộn: **Lớp làm mờ quang học (Backdrop Blur)** và **Lớp phủ sắc tố (Tint Layer)**.

| Token Name | Dark Mode (Obsidian) | Light Mode (Frosted Milk) | Ứng Dụng |
| :--- | :--- | :--- | :--- |
| `--glass-base-blur` | `30px saturate(190%)` | `30px saturate(190%)` | Độ mờ quang học phần cứng |
| `--glass-sheet-tint` | `rgba(28, 30, 36, 0.68)` | `rgba(250, 250, 252, 0.76)` | Nền Modal, Sheet, Hộp thoại chính |
| `--glass-card-tint` | `rgba(255, 255, 255, 0.05)` | `rgba(255, 255, 255, 0.65)` | Thẻ kính tương tác (Cards) |
| `--glass-recessed-tint` | `rgba(255, 255, 255, 0.04)` | `rgba(0, 0, 0, 0.03)` | Đĩa chìm cuộn danh sách (Recessed) |
| `--glass-button-secondary` | `rgba(255, 255, 255, 0.08)` | `rgba(0, 0, 0, 0.06)` | Nút thứ cấp ("Để sau", "Hủy") |
| `--glass-button-hover` | `rgba(255, 255, 255, 0.13)` | `rgba(0, 0, 0, 0.09)` | Trạng thái rê chuột nút thứ cấp |

### 2.2. Phản xạ Viền Quang Học (Specular Rim Lighting)

Kính không bao giờ có viền đơn sắc (solid 1px). Nó luôn khúc xạ ánh sáng theo hướng từ trên xuống:

```css
/* Dark Mode: Đón sáng nhẹ ở đỉnh, tan biến ở đáy */
--specular-rim-dark: linear-gradient(
  180deg,
  rgba(255, 255, 255, 0.30) 0%,
  rgba(255, 255, 255, 0.08) 100%
);

/* Light Mode: Ánh pha lê sáng rực ở đỉnh, viền mềm ở đáy */
--specular-rim-light: linear-gradient(
  180deg,
  rgba(255, 255, 255, 0.90) 0%,
  rgba(0, 0, 0, 0.12) 100%
);

/* Phản xạ ánh sáng mặt phẳng (Top Sheen) */
--specular-sheen-dark: linear-gradient(
  180deg,
  rgba(255, 255, 255, 0.08) 0%,
  rgba(255, 255, 255, 0.00) 50%
);
--specular-sheen-light: linear-gradient(
  180deg,
  rgba(255, 255, 255, 0.35) 0%,
  rgba(255, 255, 255, 0.00) 50%
);
```

### 2.3. Chiều Sâu & Bóng Đổ Vật Lý (Depth & Elevation)

Tuyệt đối tránh bóng đổ màu neon sặc sỡ. Dùng bóng đa tầng quang học (Multi-layered ambient occlusion):

```css
/* Elevation Level 1: Thẻ kính nhỏ, Nút bấm */
--shadow-elevation-1: 0 2px 6px rgba(0, 0, 0, 0.12), 0 1px 2px rgba(0, 0, 0, 0.08);

/* Elevation Level 2: Popover, Dropdown, Menu */
--shadow-elevation-2: 0 12px 28px -4px rgba(0, 0, 0, 0.28), 0 4px 10px -2px rgba(0, 0, 0, 0.16);

/* Elevation Level 3: Modal Sheet, System Dialog */
--shadow-elevation-3-dark: 0 32px 64px -12px rgba(0, 0, 0, 0.55), 0 16px 28px -6px rgba(0, 0, 0, 0.35);
--shadow-elevation-3-light: 0 24px 50px -10px rgba(0, 0, 0, 0.16), 0 10px 20px -4px rgba(0, 0, 0, 0.08);
```

### 2.4. Đường Cong Squircle (Continuous Curvature)

Apple sử dụng đường cong liên tục **Lamé Curve ($n \approx 4.5$)** thay vì góc bo elip đơn giản.
* **Hộp thoại / Sheet lớn:** `18px` hoặc `20px` (continuous)
* **App Icon 64×64:** `14px` (continuous)
* **Đĩa nội dung chìm (Recessed Plate):** `10px`
* **Nút bấm / Input:** `6px` hoặc `7px`

### 2.5. Typography & Phân Cấp Văn Bản

Ưu tiên font hệ thống chuẩn: **SF Pro Display / SF Pro Text** (trên macOS/iOS) hoặc **Inter / -apple-system** (trên Web).

| Cấp Bậc | Kích Thước | Trọng Số | Line Height | Tracking | Màu Dark Mode | Màu Light Mode |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Modal Headline** | `16px` (1rem) | `Bold (700)` | `1.3` | `-0.015em` | `rgba(255,255,255,0.95)` | `rgba(20,20,24,0.95)` |
| **Subtitle / Body** | `12.5px` (0.78rem) | `Regular (400)`| `1.45`| `normal` | `rgba(255,255,255,0.70)` | `rgba(0,0,0,0.65)` |
| **Section Label** | `12px` (0.75rem) | `Medium (500)` | `1.3` | `+0.01em` | `rgba(255,255,255,0.85)` | `rgba(0,0,0,0.80)` |
| **List / Note Text** | `12px` (0.75rem) | `Regular (400)`| `1.4` | `normal` | `rgba(255,255,255,0.90)` | `rgba(0,0,0,0.85)` |
| **Footnote / Toggle**| `11px` (0.69rem) | `Regular (400)`| `1.3` | `normal` | `rgba(255,255,255,0.65)` | `rgba(0,0,0,0.60)` |
| **Button Label** | `12.5px` (0.78rem) | `Semibold (600)`| `1.0` | `normal` | Trắng (Accent) / `0.9` | Trắng (Accent) / `0.85` |

---

## 3. Thư Viện Component Chuẩn (Component Specifications)

### 3.1. Modal / Sheet / Alert (Hộp thoại & Popup)

Bố cục 2 cột bất đối xứng kinh điển của macOS:
* **Chiều rộng chuẩn:** `530px - 550px`.
* **Cột trái:** Cột cố định `width: 64px`, chứa App Icon 64×64 với viền đón sáng `ring-1 ring-white/30` và bóng rơi tự nhiên.
* **Cột phải:** Khối nội dung chính và cụm nút tương tác, dạt sang phải.
* **Không có nút "X" tròn treo góc:** Người dùng đóng bằng nút hành động phụ hoặc phím `Escape`.

### 3.2. Action Buttons & Controls (Nút bấm & Bộ điều khiển)

* **Nút chính (Primary Accent):**
  * Màu nền: Apple System Blue (`#007aff` hoặc `rgb(10, 122, 255)`).
  * Chiều cao chuẩn: `26px` (hoặc `28px` cho touch).
  * Specular Highlight: Mép trên có viền `linear-gradient(to bottom, rgba(255,255,255,0.35), transparent)` dày 0.75pt.
  * Bóng đổ: `shadow-[0_2px_4px_rgba(0,0,0,0.15)]` (tuyệt đối không dùng bóng màu xanh phát quang).
  * Phím tắt mặc định: `Return / Enter`.
* **Nút phụ (Secondary Plain):**
  * Màu nền: Kính tối `rgba(255, 255, 255, 0.08)` (Dark) / `rgba(0, 0, 0, 0.06)` (Light).
  * Viền mảnh: `rgba(255, 255, 255, 0.14)` (Dark) / `rgba(0, 0, 0, 0.12)` (Light).
  * Chữ không bao giờ bị gãy dòng: luôn gán thuộc tính `whitespace-nowrap` hoặc `.fixedSize()`.
  * Phím tắt mặc định: `Escape`.

### 3.3. Recessed Plates (Đĩa kính khảm chìm)

Khi cần hiển thị khu vực văn bản dài (Release notes, danh sách điều khoản, thông tin hệ thống):
* Sử dụng nền chìm với độ đục tối giản: `rgba(255, 255, 255, 0.04)` (Dark) hoặc `rgba(0, 0, 0, 0.03)` (Light).
* Chiều cao tối đa: `130px - 150px` kèm thanh cuộn mềm `showsIndicators: true`.
* Viền mảnh 0.75pt tạo vết cắt rãnh trên kính: `border-white/[0.09]` (Dark) / `border-black/[0.08]` (Light).

### 3.4. Search Bar & Form Inputs (Ô tìm kiếm & Nhập liệu)

```
┌─────────────────────────────────────────────────────────────┐
│ 🔍 Tìm kiếm video, bài hát...                        [ ⌘K ] │
└─────────────────────────────────────────────────────────────┘
```
* **Nền Input:** Kính chìm `rgba(255, 255, 255, 0.06)` (Dark) / `rgba(0, 0, 0, 0.04)` (Light).
* **Viền đón sáng:** Mép trên sáng `rgba(255, 255, 255, 0.16)`, mép dưới `rgba(255, 255, 255, 0.06)`.
* **Focus Ring chuẩn macOS:** `ring-2 ring-[#007aff]/60 border-[#007aff]`.
* **Ký hiệu phím tắt (Shortcut Chip):** Nền kính nổi nhẹ `rgba(255, 255, 255, 0.10)`, chữ `10.5px`, bo tròn `4px`.

### 3.5. Floating Header & Island Toast (Thanh điều hướng nổi & Toast)

* **Thanh Header kính nổi:**
  * Dùng cố định ở đỉnh trang: `backdrop-filter: blur(20px) saturate(180%)`.
  * Nền: `rgba(15, 15, 18, 0.72)` (Dark) / `rgba(255, 255, 255, 0.80)` (Light).
  * Viền đáy ngăn cách: Specular divider `0.75pt` (`rgba(255, 255, 255, 0.10)` / `rgba(0, 0, 0, 0.08)`).
* **Capsule Toast (Dynamic Island Style):**
  * Hình dạng: `Capsule` hoàn chỉnh.
  * Kích thước: Chiều cao `36px - 40px`, padding ngang `16px`.
  * Hiệu ứng: Trôi nổi với bóng đổ `0 16px 32px rgba(0, 0, 0, 0.35)`.

---

## 4. Triển Khai Web (Tailwind CSS / Next.js / CSS Variables)

### 4.1. File `globals.css` (Tích hợp trọn gói)

```css
:root {
  /* Common Transition */
  --liquid-spring: cubic-bezier(0.16, 1, 0.3, 1);
}

/* 1. Dark Mode Liquid Glass Canvas */
.alg-glass-dark {
  background: linear-gradient(
    180deg,
    rgba(32, 34, 40, 0.65) 0%,
    rgba(22, 23, 28, 0.72) 100%
  );
  backdrop-filter: blur(28px) saturate(190%);
  -webkit-backdrop-filter: blur(28px) saturate(190%);
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: 
    0 32px 64px -12px rgba(0, 0, 0, 0.55),
    0 16px 28px -6px rgba(0, 0, 0, 0.35),
    inset 0 1px 1px 0 rgba(255, 255, 255, 0.28),
    inset 0 -1px 1px 0 rgba(255, 255, 255, 0.04);
}

/* 2. Light Mode Liquid Glass Canvas */
.alg-glass-light {
  background: linear-gradient(
    180deg,
    rgba(255, 255, 255, 0.78) 0%,
    rgba(248, 249, 252, 0.75) 100%
  );
  backdrop-filter: blur(28px) saturate(190%);
  -webkit-backdrop-filter: blur(28px) saturate(190%);
  border: 1px solid rgba(255, 255, 255, 0.45);
  box-shadow: 
    0 24px 50px -10px rgba(0, 0, 0, 0.16),
    0 10px 20px -4px rgba(0, 0, 0, 0.08),
    inset 0 1px 1.5px 0 rgba(255, 255, 255, 0.95),
    inset 0 -1px 1px 0 rgba(0, 0, 0, 0.06);
}

/* 3. Recessed Frosted Plate */
.alg-recessed-dark {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.09);
  box-shadow: inset 0 1px 2px 0 rgba(0, 0, 0, 0.25);
}
.alg-recessed-light {
  background: rgba(0, 0, 0, 0.03);
  border: 1px solid rgba(0, 0, 0, 0.08);
  box-shadow: inset 0 1px 2px 0 rgba(0, 0, 0, 0.04);
}

/* 4. Secondary Frosted Button */
.alg-btn-secondary-dark {
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.14);
  color: rgba(255, 255, 255, 0.90);
  transition: all 0.15s var(--liquid-spring);
}
.alg-btn-secondary-dark:hover {
  background: rgba(255, 255, 255, 0.13);
  border-color: rgba(255, 255, 255, 0.20);
}

.alg-btn-secondary-light {
  background: rgba(0, 0, 0, 0.06);
  border: 1px solid rgba(0, 0, 0, 0.12);
  color: rgba(0, 0, 0, 0.85);
  transition: all 0.15s var(--liquid-spring);
}
.alg-btn-secondary-light:hover {
  background: rgba(0, 0, 0, 0.09);
  border-color: rgba(0, 0, 0, 0.18);
}

/* 5. Primary Apple Accent Button */
.alg-btn-primary {
  background: #007aff;
  color: #ffffff;
  box-shadow: 
    0 2px 4px rgba(0, 0, 0, 0.15),
    inset 0 1px 0.5px rgba(255, 255, 255, 0.35);
  transition: all 0.15s var(--liquid-spring);
}
.alg-btn-primary:hover {
  background: #0071eb;
}
.alg-btn-primary:active {
  background: #0062cc;
  transform: scale(0.98);
}
```

### 4.2. Universal Dialog Component (React / Next.js)

```tsx
import React, { useEffect } from 'react';

export interface LiquidGlassDialogProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  subtitle: string;
  iconSrc?: string;
  notesLabel?: string;
  notes?: string[];
  cancelText?: string;
  confirmText?: string;
  isDark?: boolean;
}

export const LiquidGlassDialog: React.FC<LiquidGlassDialogProps> = ({
  isOpen,
  onClose,
  onConfirm,
  title,
  subtitle,
  iconSrc = "/assets/icon.png",
  notesLabel = "Nội dung cập nhật:",
  notes = [],
  cancelText = "Để sau",
  confirmText = "Cập nhật ngay",
  isDark = true,
}) => {
  // Lắng nghe phím Escape chuẩn công thái học
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) onClose();
      if (e.key === 'Enter' && isOpen) onConfirm();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose, onConfirm]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/35 backdrop-blur-[3px] animate-fade-in">
      <div
        className={`w-full max-w-[530px] rounded-[18px] p-6 select-none ${
          isDark ? 'alg-glass-dark text-white' : 'alg-glass-light text-neutral-900'
        }`}
        style={{
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", Roboto, sans-serif'
        }}
      >
        <div className="flex items-start gap-5">
          {/* Cột 1: App Icon */}
          <div className="flex-shrink-0 pt-1">
            <div className="w-16 h-16 rounded-[14px] overflow-hidden shadow-[0_8px_16px_rgba(0,0,0,0.22)] ring-1 ring-white/30 bg-black/10">
              <img src={iconSrc} alt="Icon" className="object-cover w-full h-full" />
            </div>
          </div>

          {/* Cột 2: Nội dung phân cấp chuẩn Apple HIG */}
          <div className="flex-1 min-w-0 space-y-3.5">
            <div>
              <h3 className="text-[16px] font-bold tracking-tight leading-snug">
                {title}
              </h3>
              <p className={`text-[12.5px] mt-1 leading-relaxed ${isDark ? 'text-white/70' : 'text-black/65'}`}>
                {subtitle}
              </p>
            </div>

            {notes.length > 0 && (
              <>
                <div className={`text-[12px] font-medium ${isDark ? 'text-white/85' : 'text-black/80'}`}>
                  {notesLabel}
                </div>
                <div
                  className={`max-h-[140px] overflow-y-auto rounded-[10px] p-3 text-[12px] space-y-2 ${
                    isDark ? 'alg-recessed-dark text-white/90' : 'alg-recessed-light text-black/85'
                  }`}
                >
                  {notes.map((line, idx) => (
                    <div key={idx} className="flex items-start gap-2 leading-relaxed">
                      <span className={isDark ? 'text-white/40' : 'text-black/35'}>•</span>
                      <span>{line}</span>
                    </div>
                  ))}
                </div>
              </>
            )}

            {/* Cụm nút chân trang */}
            <div className="flex items-center justify-end gap-2.5 pt-1">
              <button
                type="button"
                onClick={onClose}
                className={`px-3.5 h-[26px] text-[12.5px] rounded-[6px] whitespace-nowrap ${
                  isDark ? 'alg-btn-secondary-dark' : 'alg-btn-secondary-light'
                }`}
              >
                {cancelText}
              </button>

              <button
                type="button"
                onClick={onConfirm}
                className="px-3.5 h-[26px] text-[12.5px] font-semibold rounded-[6px] alg-btn-primary flex items-center gap-1.5 whitespace-nowrap"
              >
                <svg className="w-3 h-3 fill-current" viewBox="0 0 16 16">
                  <path d="M8 12l-4-4h2.5V3h3v5H12l-4 4zm-6 2h12v1.5H2V14z" />
                </svg>
                <span>{confirmText}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
```

---

## 5. Triển Khai Native macOS / iOS (SwiftUI)

### 5.1. View Modifier Kính Quang Học (Reusable SwiftUI Modifier)

```swift
import SwiftUI
import AppKit

// Cấu trúc nền Vibrancy phần cứng
public struct LiquidVisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .popover
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    public var state: NSVisualEffectView.State = .active
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// Modifier đóng gói trọn gói định luật vật lý Liquid Glass
public struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat = 18
    
    private var isDark: Bool { colorScheme == .dark }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. Hardware Optical Blur
                    LiquidVisualEffectBackground()
                    
                    // 2. Liquid Glass Translucent Tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isDark
                                ? LinearGradient(
                                    colors: [
                                        Color(red: 32/255, green: 34/255, blue: 40/255).opacity(0.65),
                                        Color(red: 22/255, green: 23/255, blue: 28/255).opacity(0.72)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.75),
                                        Color(red: 248/255, green: 249/255, blue: 252/255).opacity(0.78)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  )
                        )
                    
                    // 3. Ambient Top Sheen
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.08 : 0.25),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // 4. Specular Rim Hairline (0.75pt)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.30 : 0.80),
                                Color.white.opacity(isDark ? 0.08 : 0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.16), radius: 26, y: 12)
    }
}

public extension View {
    func liquidGlassModal(cornerRadius: CGFloat = 18) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}
```

---

## 6. Tiêu Chuẩn Accessibility & Chế Độ Giảm Trong Suốt

Khi người dùng bật tính năng **"Reduce Transparency"** trong macOS / iOS Settings hoặc Windows Accessibility:

```css
/* Web CSS: Hỗ trợ tự động fallback sang nền đục khi bật Reduce Transparency */
@media (prefers-reduced-transparency: reduce) {
  .alg-glass-dark {
    background: #1c1d22 !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
  }
  .alg-glass-light {
    background: #f7f7f9 !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
  }
}
```

Trong SwiftUI:
```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

// Tự động chuyển fill từ .opacity(0.65) sang Solid Color nếu reduceTransparency == true.
```

---

## 7. Checklist Phê Duyệt Thiết Kế (Design Review Checklist)

Mỗi khi phát triển xong một màn hình hoặc popup theo phong cách này, hãy dùng checklist này để nghiệm thu:

- [ ] **1. Kiểm tra khúc xạ (Vibrancy):** Khi di chuyển popup đè lên video hoặc wallpaper rực rỡ, màu nền đằng sau có lờ mờ phản chiếu xuyên qua không? *(Nếu biến thành mảng xám đục ngầu = Chưa đạt, phải hạ độ đục lớp phủ).*
- [ ] **2. Kiểm tra viền đón sáng (Specular Rim):** Mép đỉnh trên cùng có sáng hơn mép đáy dưới không?
- [ ] **3. Kiểm tra App Icon:** Icon có hình squircle mềm mại, bóng đổ xám tự nhiên không? *(Nếu có vệt sáng blur đỏ/tím lòe loẹt = Loại bỏ ngay).*
- [ ] **4. Kiểm tra nút đóng:** Cửa sổ có bị gắn nút tròn "X" trôi nổi góc trên kiểu web không? *(Đã thay bằng nút "Để sau" hoặc phím `Escape` chưa?)*
- [ ] **5. Kiểm tra nút bấm:** Nút bấm có bị bẻ đôi chữ không? *(Text phải nằm trên một hàng duy nhất).*
- [ ] **6. Kiểm tra bảng danh sách:** Vùng chứa danh sách có dùng **Recessed Frosted Plate** nền mỏng 4% không? *(Tuyệt đối không lồng thêm card trắng viền dày).*
- [ ] **7. Kiểm tra độ tương phản văn bản:** Chữ tiêu đề và nội dung có đạt chuẩn tương phản tối thiểu **4.5:1 (WCAG AA)** trên nền kính không?

---
*Tài liệu này là quy chuẩn thiết kế chính thức được lưu trữ tại codebase AuraTube và có thể tái sử dụng trực tiếp cho tất cả các ứng dụng Web / Native khác.*
