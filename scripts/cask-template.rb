# Homebrew Cask 템플릿 — 개인 tap용
#
# 사용법:
#   1. GitHub에 `homebrew-malmandu` 리포 생성 (정확히 이 이름이어야 함)
#   2. 리포 루트에 `Casks/` 폴더 생성
#   3. 이 파일을 `Casks/malmandu.rb`로 복사
#   4. release.sh가 출력한 VERSION과 SHA256을 아래 값에 채우기
#   5. DMG 파일을 GitHub Release로 업로드 (태그명: v<VERSION>)
#   6. 사용자 설치:
#        brew tap blacktoast/malmandu
#        brew install --cask malmandu
#
# 서명 안 된 앱이므로 postflight에서 quarantine 플래그를 제거해
# "손상된 앱" 경고 없이 바로 실행 가능하게 만든다.

cask "malmandu" do
  version "0.0.1"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_SCRIPT"

  url "https://github.com/blacktoast/malmandu/releases/download/v#{version}/Malmandu-#{version}.dmg"
  name "Malmandu"
  name "말만두"
  desc "macOS menu bar voice-to-text tool (Groq Whisper, Soniox)"
  homepage "https://github.com/blacktoast/malmandu"

  depends_on macos: ">= :sequoia"

  app "Malmandu.app"

  postflight do
    # 서명/공증이 없으므로 Gatekeeper quarantine 플래그를 수동 제거.
    # 이게 없으면 첫 실행 시 "손상되었거나 확인할 수 없는 개발자" 경고가 뜬다.
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Malmandu.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.malmandu.app.plist",
    "~/Library/Application Support/Malmandu",
    "~/Library/Caches/com.malmandu.app",
  ]
end
