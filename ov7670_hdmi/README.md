# OV7670 640x480 → PSRAM → HDMI (Tang Nano 9K)

Camera OV7670 (không FIFO) đọc 640x480 RGB565, đệm bằng **PSRAM tích hợp** của GW1NR-9
(triple buffer), xuất **HDMI/DVI 640x480@60Hz** thời gian thực. Chưa có Sobel; đã chừa sẵn khe
`video_proc.v`. Pin camera/nút/LED giữ nguyên project cũ, vẫn tránh chân 28 và 30.

## 1. Phải làm trước khi build: tạo IP PSRAM (Gowin mã hoá, không đóng gói sẵn được)

`Tools → IP Core Generator → Memory Control → PSRAM Memory Interface HS`

| Mục | Giá trị |
|---|---|
| Module Name | `PSRAM_Memory_Interface_HS_Top` (mặc định, KHÔNG đổi) |
| Channel Number | **2** (dual channel) |
| Memory Clock | **81 MHz** |
| Burst Mode | **64** |
| Còn lại | mặc định (Initial latency 6, Fixed, 1:2) |

Sau khi sinh, thêm file `.v` / `.ipc` của IP vào project (Project → Add Files). Nếu tên cổng của IP sinh ra
khác, sửa khối `u_psram` trong `src/frame_store.v` (đang theo IPUG943: `clk, memory_clk, pll_lock, rst_n,
clk_out, init_calib0/1, cmd0/1, cmd_en0/1, addr0/1, wr_data0/1, data_mask0/1, rd_data0/1, rd_data_valid0/1`).

## 2. Build

1. Mở `ov7670_hdmi.gprj` (nếu IDE không mở được file này: New Project, chip **GW1NR-LV9QN88PC6/I5**,
   rồi Add Files toàn bộ `src/*.v`, `.cst`, `.sdc`).
2. Top module: `ov7670_top`. Synthesize → Place & Route → nạp.
3. Nếu P&R báo không tìm thấy pin `u_fs/u_psram/clkdiv_s0/CLKOUT` trong `.sdc`: mở netlist, đổi đường dẫn
   tới pin CLKOUT của CLKDIV trong IP (đó là `clk_mem` = 40.5 MHz).

## 3. Kiến trúc

```
OV7670 ──PCLK 13.5MHz──► ov7670_capture ─► line_buf (2 dòng x 160 từ x 64b, BSRAM)
                                             │  clk_mem 40.5 MHz
                                             ▼
                                        frame_store ◄──► PSRAM (IP Gowin, 81 MHz, 2 kênh x 32b)
                                             │  3 bộ đệm khung (bw / bl / bd), burst 128 B
                                             ▼
                                         afifo64 (256 x 64b, BSRAM, gray pointer)
                                             │  pix_clk 25.2 MHz
                                             ▼
                      hdmi_scan ─► video_proc (chỗ gắn Sobel) ─► hdmi_tx (TMDS + OSER10 126 MHz)
```

* 1 từ 64 bit = 4 pixel RGB565. 1 burst = 16 từ = 64 pixel. 1 dòng = 10 burst, 1 khung = 4800 burst.
* Triple buffer: camera (~17 fps) và HDMI (60 Hz) chạy lệch nhau mà không xé hình; HDMI lặp lại khung cũ
  cho đến khi có khung mới hoàn chỉnh.
* Băng thông: ghi ≈ 10 MB/s, đọc HDMI ≈ 50 MB/s, PSRAM đáp ứng khoảng 160+ MB/s (CMD_INTERVAL = 32).
* Mỗi khung HDMI (dòng 481–482) có một nhịp `flush_req`: reset FIFO, đổi bộ đệm, đọc lại từ đầu khung.
* Chưa có khung camera nào (hoặc PSRAM chưa calib) → màn hình hiện 8 thanh màu, dùng để kiểm tra
  đường HDMI độc lập với camera.

## 4. Nút và LED

* **S1** (chân 4): đóng băng / tiếp tục (giữ nguyên khung hiện tại).
* **S2** (chân 3): bật/tắt color bar bên trong cảm biến OV7670.
* LED (sáng = 1): 0 = đã nạp thanh ghi camera; 1 = cảm biến trả ACK; 2 = có PCLK; 3 = có VSYNC;
  4 = PSRAM sẵn sàng và đã có khung (nhấp nháy nhanh = tràn hàng đợi ghi hoặc FIFO HDMI cạn);
  5 = đóng băng (sáng) / color bar (nhấp nháy chậm).

## 5. Gỡ lỗi theo thứ tự

1. Chỉ thấy 8 thanh màu trên màn hình → HDMI ổn. Nếu không có hình: kiểm tra `lock_hdmi`, cáp,
   thử màn hình khác (một số màn hình khó tính với DVI không có data island).
2. LED0/1 sáng, LED2/3 nhấp nháy → camera ổn. LED4 không sáng → PSRAM chưa calib hoặc chưa có khung.
3. Bấm S2 (color bar cảm biến): nếu color bar lên màn hình đúng mà ảnh thật hỏng → vấn đề ở camera/dây;
   nếu color bar cũng hỏng → vấn đề ở đường PSRAM.
4. Hình bị lệch/xé theo cột 4 pixel hoặc nhiễu → nghi thời điểm `wr_data` so với `cmd_en` hoặc bước
   địa chỉ burst (xem mục 6).

## 6. Những giả định CHƯA kiểm chứng trên phần cứng

Code chưa được mô phỏng hay tổng hợp (môi trường tạo ra không có công cụ HDL). Chỉ kiểm tra cấu trúc
bằng script (khớp cổng, cân bằng begin/end, tên chưa khai báo) và rà soát logic bằng tay.

* **Thời điểm `wr_data`:** giả định từ dữ liệu đầu đi cùng chu kỳ với `cmd_en`, rồi 15 từ liên tiếp
  (theo ví dụ element14). Nếu hình sai, thử trễ dữ liệu 1–2 chu kỳ trong `A_WCMD/A_WSTR`.
* **Bước địa chỉ:** burst 64 byte mỗi kênh → địa chỉ tăng 32 (`{n, 5'b00000}`), suy ra từ ví dụ burst 32 byte
  bước 16. Nếu khác, sửa `wr_addr` / `rd_addr` trong `frame_store.v`.
* **`CMD_INTERVAL = 32`:** tài liệu Gowin ghi tối thiểu 27 chu kỳ cho burst 64. Có thể tăng nếu thấy lỗi.
* **Pin HDMI** (69/68, 71/70, 73/72, 75/74) xác nhận qua 2 nguồn công khai; thứ tự kênh D0 = xanh dương,
  D1 = xanh lá, D2 = đỏ theo chuẩn DVI. Nếu màu bị hoán đổi, đổi dây `b/g/r` trong `hdmi_tx.v`.
* **Thứ tự pixel/byte:** `{byte1, byte2}` = RGB565 chuẩn như project cũ. Nếu màu sai (đỏ↔xanh), đổi
  thứ tự byte trong `ov7670_capture.v` (`pix = {hi, d}`) hoặc bit COM15/TSLB.
* **Tốc độ khung camera:** 13.5 MHz PCLK ≈ 17 fps. Muốn ≈ 34 fps đặt `CLKRC_VAL = 8'h00` ở top
  (cần dây camera tốt, PCLK 27 MHz).

## 7. Gắn Sobel sau này

Sửa `src/video_proc.v` (miền `pix_clk`, luồng pixel liên tục `de/hs/vs`): đổi sang xám, 2 line buffer
640x8 bit (BSRAM còn trống nhiều: line_buf + FIFO chỉ dùng khoảng 4 khối), cửa sổ 3x3, trễ `hs/vs/de`
đúng bằng độ trễ bộ lọc. Có thể dùng cổng `sel` để chọn ảnh gốc / ảnh Sobel.

## 8. File

| File | Vai trò |
|---|---|
| `ov7670_top.v` | Top: nối toàn bộ, nút, LED |
| `clk_gen.v` | PLL 81 MHz (PSRAM), PLL 126 MHz + CLKDIV/5 = 25.2 MHz (HDMI) |
| `ov7670_init.v`, `sccb_master.v`, `btn_ctrl.v` | Giữ từ project cũ (init thêm `CLKRC_VAL`) |
| `ov7670_capture.v` | Thu 640x480, gom 4 pixel/từ 64b vào line buffer |
| `line_buf.v` | 2 dòng ping-pong, 2 cổng clock |
| `frame_store.v` | Bọc IP PSRAM, hàng đợi dòng, triple buffer, đọc/ghi burst |
| `afifo64.v` | FIFO bất đồng bộ clk_mem → pix_clk |
| `hdmi_scan.v` | Timing 640x480@60, đọc FIFO, thanh màu dự phòng |
| `video_proc.v` | Khe Sobel (đang đi thẳng) |
| `tmds_encoder.v`, `hdmi_tx.v` | TMDS 8b/10b, OSER10, ELVDS_OBUF |
| `ov7670_tn9k.cst`, `.sdc` | Ràng buộc chân và timing |

Đã bỏ: `frame_buf.v` (BRAM 160x120), `frame_sender.v`, `uart_tx8n1.v` (UART không còn dùng).
