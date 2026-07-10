#!/usr/bin/env zsh

set -euo pipefail

template_path="supabase/templates/email-change-otp.html"

grep -Fq '[auth.email.template.email_change]' supabase/config.toml
grep -Fq 'otp_length = 8' supabase/config.toml
grep -Fq 'subject = "MyLeafy 绑定邮箱验证码"' supabase/config.toml
grep -Fq 'content_path = "./supabase/templates/email-change-otp.html"' supabase/config.toml
grep -Fq '{{ .Token }}' "$template_path"
grep -Fq '{{ .NewEmail }}' "$template_path"

if grep -Fq '登录别名' "$template_path"; then
    print -u2 'Email-change template must describe notification use only.'
    exit 1
fi

if grep -Fq '{{ .ConfirmationURL }}' "$template_path" || grep -Fq '{{ .TokenHash }}' "$template_path"; then
    print -u2 'Email-change template must not contain a confirmation link or token hash.'
    exit 1
fi
