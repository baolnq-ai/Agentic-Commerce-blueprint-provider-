# Quy trình push github khi code xong 1 chức năng hay fix xong 1 bug.

## 1.Đồng bộ nhánh làm việc trước khi code xong hẳn
- Chuyển về nhánh của bạn.
- Commit phần đang làm dở hoặc stash tạm.
- Pull từ nhánh gốc của team theo kiểu rebase để lịch sử gọn.

### Trường hợp đang code dở, cần cập nhật main nhưng chưa muốn push code của mình
- Cách 1 (khuyên dùng): stash code đang làm dở
	- `git stash push -u -m "wip: dang lam do"`
	- `git fetch origin && git rebase origin/main` (hoặc `git pull --rebase origin main`)
	- `git stash pop` để lấy lại code đang làm.
- Cách 2: commit tạm local rồi cập nhật main
	- `git add . && git commit -m "wip: tam luu local"`
	- `git pull --rebase origin main`
	- Khi chuẩn bị push thật thì squash/reword commit WIP cho sạch lịch sử.
- Lưu ý:
	- Không bắt buộc phải push ngay khi chỉ muốn cập nhật code mới từ `main`.
	- Nếu có conflict thì resolve xong mới tiếp tục code.
## 2.Hoàn thiện và tự kiểm tra trước khi commit cuối
Chạy test/lint/build tối thiểu.
Chạy nhanh chức năng chính vừa sửa để chắc không vỡ luồng cũ.
Soát lại file thừa, secret, log, file tạm.

### Bắt buộc luôn có CI/CD trên Git
- Mọi nhánh push lên GitHub phải có CI/CD chạy tự động bằng GitHub Actions hoặc pipeline tương đương.
- Không merge PR khi CI/CD còn đỏ, bị skip bất thường, hoặc chưa chạy đủ các job chính.
- Production gate tối thiểu phải có 4 nhóm kiểm tra: compatibility matrix, quality tests, security scan, build artifacts.
- Với dự án chạy đa nền tảng, CI phải có kiểm tra Linux và Windows; matrix kiến trúc phải đủ amd64/arm64 cho các OS hỗ trợ (bao gồm Windows arm64 khi runner sẵn có).
- Khi sửa pipeline, phải mở PR như code bình thường và ghi rõ job nào đã chạy pass.

### Bộ CI/CD production-grade đang áp dụng
- Compatibility matrix: Linux/amd64, Linux/arm64, Windows/amd64, Windows/arm64.
- Backend quality gate: ruff lint + pytest smoke/contract + coverage xml artifact.
- Frontend quality gate: eslint + typecheck + build.
- Security gate: pip-audit cho backend dependencies và npm audit mức high cho frontend dependencies.
- Artifact/report gate: bắt buộc upload report coverage và report security để review khi fail.

### Quy tắc merge production
- Bật Branch Protection trên `main`, bắt buộc pass toàn bộ required checks trước khi merge.
- Bắt buộc ít nhất 1 reviewer approve với các thay đổi động tới `.github/workflows/` hoặc script deploy/setup.
- Không cho phép merge nếu thiếu test evidence trong mô tả PR (link run CI hoặc log local).
- Không merge commit có secret/token trong diff; luôn scan trước khi merge.

### Danh sách workflow hiện tại
- `.github/workflows/ci-matrix-linux.yml`: kiểm tra tương thích đa OS/arch.
- `.github/workflows/ci-cross-platform.yml`: kiểm tra chéo bổ sung theo OS.
- `.github/workflows/ci-production-gates.yml`: quality + security + artifact gates cho production.

Ví dụ kiểm tra local trước khi push:

```bash
./setup.sh --self-test
cd backend && python -m pip install -e '.[dev]' && ruff check app && pytest -q ../backend/tests
cd ../frontend && npm ci && npm run lint && npm run typecheck && npm run build
```

## 3.Commit đúng chuẩn
Chia commit nhỏ theo ý nghĩa, message rõ ràng.
Tránh một commit quá to gom nhiều việc không liên quan.
## 4.Push lên nhánh cá nhân
Push nhánh của bạn lên remote.
Nếu bị reject thì pull rebase rồi push lại.
## 5.Tạo PR/MR 
Mô tả rõ: đã sửa gì, vì sao sửa, ảnh hưởng gì.
Đính kèm cách test và kết quả test.
Gắn reviewer/leader để merge.
## 6.Sau khi được merge
Cập nhật lại nhánh local từ nhánh chính.
Dọn nhánh feature đã xong.
