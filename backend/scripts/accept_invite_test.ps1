$ErrorActionPreference = 'Stop'
$base = 'http://localhost:8080'
$suffix = Get-Date -Format 'HHmmssfff'
$ownerPhone = "+996702$suffix"
$memberPhone = "+996703$suffix"

function JsonBody($value) { return ($value | ConvertTo-Json -Compress) }
function SmsLogin($phone) {
  $req = Invoke-RestMethod -Uri "$base/api/v1/auth/sms/request" -Method Post -ContentType 'application/json' -Body (JsonBody @{phone=$phone})
  return (Invoke-RestMethod -Uri "$base/api/v1/auth/sms/verify" -Method Post -ContentType 'application/json' -Body (JsonBody @{phone=$phone;code=$req.dev_code}))
}

$owner = SmsLogin $ownerPhone
$ownerHeaders = @{ Authorization = "Bearer $($owner.access_token)" }
$project = Invoke-RestMethod -Uri "$base/api/v1/projects" -Method Post -Headers $ownerHeaders -ContentType 'application/json' -Body (JsonBody @{name="Invite Accept $suffix";address='Bishkek';budget_amount=1000;currency='KGS'})
$member = SmsLogin $memberPhone
$inviteToken = "manual-accept-$suffix"
$sha = [Security.Cryptography.SHA256]::Create()
$hash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($inviteToken)) | ForEach-Object { $_.ToString('x2') }) -join '')
$sha.Dispose()
$sql = "INSERT INTO project_invites (project_id, invited_by, phone, role, token_hash, expires_at) VALUES ('$($project.id)', '$($owner.user_id)', '$memberPhone', 'viewer', '$hash', now() + interval '1 hour')"
Set-Location 'F:\Users\kosho\Documents\OnlineProrab_Test'
& docker compose exec -T postgres psql -U onlineprorab -d onlineprorab -v ON_ERROR_STOP=1 -c $sql
$accept = Invoke-WebRequest -Uri "$base/api/v1/project-invites/accept" -Method Post -Headers @{Authorization="Bearer $($member.access_token)"} -ContentType 'application/json' -Body (JsonBody @{invite_token=$inviteToken}) -UseBasicParsing
if ([int]$accept.StatusCode -ne 200) { throw "accept status $($accept.StatusCode)" }
Write-Host "ACCEPT_INVITE_SUCCESS status=$($accept.StatusCode) project_id=$($project.id) role=$($accept.Content | ConvertFrom-Json | Select-Object -ExpandProperty role)"
