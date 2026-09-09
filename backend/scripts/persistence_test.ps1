$ErrorActionPreference = 'Stop'
$base = 'http://localhost:8080'
$suffix = Get-Date -Format 'HHmmssfff'
$phone = "+996704$suffix"
$source = 'F:\Users\kosho\Documents\OnlineProrab_Test\mobile\assets\branding\stroy_icon.png'
$download = "F:\Users\kosho\Documents\OnlineProrab_Test\persisted_$suffix.png"

function Body($value) { return ($value | ConvertTo-Json -Compress) }
$request = Invoke-RestMethod -Uri "$base/api/v1/auth/sms/request" -Method Post -ContentType 'application/json' -Body (Body @{phone=$phone})
$login = Invoke-RestMethod -Uri "$base/api/v1/auth/sms/verify" -Method Post -ContentType 'application/json' -Body (Body @{phone=$phone;code=$request.dev_code})
$headers = @{ Authorization = "Bearer $($login.access_token)" }
$project = Invoke-RestMethod -Uri "$base/api/v1/projects" -Method Post -Headers $headers -ContentType 'application/json' -Body (Body @{name="Persistence $suffix";address='Bishkek';budget_amount=777;currency='KGS'})
$uploadRaw = (& curl.exe --silent --show-error -X POST "$base/api/v1/files/upload" --header "Authorization: Bearer $($login.access_token)" --form "project_id=$($project.id)" --form 'kind=photo' --form "file=@$source;type=image/png" | Out-String)
$uploaded = $uploadRaw | ConvertFrom-Json
if (-not $uploaded.id) { throw "upload did not return file id" }

Set-Location 'F:\Users\kosho\Documents\OnlineProrab_Test'
& docker compose restart postgres
for ($i=0; $i -lt 30; $i++) {
  $pg = (& docker inspect --format '{{.State.Health.Status}}' onlineprorab_test-postgres-1 2>$null)
  if ($pg.Trim() -eq 'healthy') { break }
  Start-Sleep -Seconds 1
}
& docker compose restart api
$health = $null
for ($i=0; $i -lt 30; $i++) {
  try { $health = Invoke-WebRequest -Uri "$base/ready" -UseBasicParsing; if ([int]$health.StatusCode -eq 200) { break } } catch {}
  Start-Sleep -Seconds 1
}
if (-not $health -or [int]$health.StatusCode -ne 200) { throw 'API did not become ready after restart' }

$projectAfter = Invoke-RestMethod -Uri "$base/api/v1/projects/$($project.id)" -Headers $headers
$filesAfter = Invoke-RestMethod -Uri "$base/api/v1/files?project_id=$($project.id)" -Headers $headers
Invoke-WebRequest -Uri "$base/api/v1/files/download?file_id=$($uploaded.id)" -Headers $headers -OutFile $download -UseBasicParsing
$sourceHash = (Get-FileHash $source -Algorithm SHA256).Hash
$downloadHash = (Get-FileHash $download -Algorithm SHA256).Hash
if ($projectAfter.id -ne $project.id -or $downloadHash -ne $sourceHash) { throw 'persisted project or file mismatch' }
Write-Host "PERSISTENCE_SUCCESS project=$($projectAfter.id) files=$(@($filesAfter.items).Count) file_hash_match=True"
