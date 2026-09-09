$ErrorActionPreference = 'Stop'
$Base = 'http://localhost:8080'
$Results = @()
$CoverPath = 'F:\Users\kosho\Documents\OnlineProrab_Test\mobile\assets\branding\stroy_icon.png'
$Suffix = (Get-Date -Format 'HHmmssfff')
$OwnerPhone = "+996701$Suffix"
$MemberPhone = "+996700$Suffix"

function Invoke-Case {
  param(
    [string]$Name,
    [string]$Method,
    [string]$Path,
    [int]$Expected,
    [string]$Token = '',
    [string]$Body = '',
    [string[]]$Forms = @(),
    [string]$OutFile = ''
  )
  $status = 0
  $responseBody = ''
  if ($OutFile -or $Forms.Count -gt 0) {
    $curlArgs = @('--silent','--show-error','--write-out','CODE:%{http_code}','-X',$Method,("$Base$Path"))
    if ($Token) { $curlArgs += @('--header',"Authorization: Bearer $Token") }
    foreach ($form in $Forms) { $curlArgs += @('--form',$form) }
    if ($OutFile) { $curlArgs += @('--output',$OutFile) }
    $raw = (& curl.exe @curlArgs 2>&1 | Out-String)
    $marker = $raw.LastIndexOf('CODE:')
    $status = [int]$raw.Substring($marker + 5).Trim()
    if ($OutFile) { $responseBody = '' } else { $responseBody = $raw.Substring(0,$marker).Trim() }
  } else {
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $request = @{ Uri=("$Base$Path"); Method=$Method; Headers=$headers; UseBasicParsing=$true }
    if ($Body) { $request['ContentType'] = 'application/json'; $request['Body'] = $Body }
    if ($OutFile) { $request['OutFile'] = $OutFile }
    try {
      $response = Invoke-WebRequest @request
      $status = [int]$response.StatusCode
      if (-not $OutFile) { $responseBody = [string]$response.Content }
    } catch {
      $webResponse = $_.Exception.Response
      if ($webResponse) {
        $status = [int]$webResponse.StatusCode
        $reader = New-Object System.IO.StreamReader($webResponse.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $reader.Dispose()
      } else { throw }
    }
  }
  $ok = ($status -eq $Expected)
  $record = [pscustomobject]@{ Name=$Name; Method=$Method; Path=$Path; Expected=$Expected; Actual=$status; Passed=$ok; Body=$responseBody }
  $script:Results += $record
  Write-Host ("{0} {1} {2} expected={3} actual={4}" -f ($(if($ok){'PASS'}else{'FAIL'}),$Method,$Name,$Expected,$status))
  if (-not $ok) { Write-Host ("  body: " + $responseBody) }
  return $record
}

function Get-Json($Record) {
  if (-not $Record.Body) { return $null }
  return ($Record.Body | ConvertFrom-Json)
}

$null = Invoke-Case 'health' 'GET' '/health' 200
$null = Invoke-Case 'ready' 'GET' '/ready' 200
$null = Invoke-Case 'unauthorized projects' 'GET' '/api/v1/projects' 401
$null = Invoke-Case 'unauthorized realtime' 'GET' '/api/v1/realtime' 401
$null = Invoke-Case 'unauthorized support channels' 'GET' '/api/v1/support/channels' 401
$null = Invoke-Case 'unauthorized support ticket' 'POST' '/api/v1/support/tickets' 401 -Body (@{channel='telegram';message='unauthorized'}|ConvertTo-Json -Compress)
$null = Invoke-Case 'sms verify wrong method' 'GET' '/api/v1/auth/sms/verify' 405
$null = Invoke-Case 'sms invalid json' 'POST' '/api/v1/auth/sms/request' 400 -Body '{'
$authRequest = @{phone=$OwnerPhone; name='API test owner'} | ConvertTo-Json -Compress
$r = Invoke-Case 'sms request' 'POST' '/api/v1/auth/sms/request' 202 -Body $authRequest
$j = Get-Json $r
$code = [string]$j.dev_code
$r = Invoke-Case 'sms verify' 'POST' '/api/v1/auth/sms/verify' 200 -Body (@{phone=$OwnerPhone;code=$code}|ConvertTo-Json -Compress)
$j = Get-Json $r
$Token = [string]$j.access_token
$OwnerId = [string]$j.user_id
$r = Invoke-Case 'create session' 'POST' '/api/v1/auth/session' 201 -Token $Token -Body (@{device_name='full-api-test'}|ConvertTo-Json -Compress)
$j = Get-Json $r
$Refresh = [string]$j.refresh_token
$r = Invoke-Case 'refresh session' 'POST' '/api/v1/auth/session/refresh' 200 -Body (@{refresh_token=$Refresh}|ConvertTo-Json -Compress)
$j = Get-Json $r
$Token = [string]$j.access_token
$Refresh = [string]$j.refresh_token
$null = Invoke-Case 'logout session' 'POST' '/api/v1/auth/session/logout' 200 -Body (@{refresh_token=$Refresh}|ConvertTo-Json -Compress)

$null = Invoke-Case 'support channels' 'GET' '/api/v1/support/channels' 200 -Token $Token
$supportBody = @{channel='telegram';subject='API test';message='Support ticket storage test'} | ConvertTo-Json -Compress
$r = Invoke-Case 'create support ticket without bot keys' 'POST' '/api/v1/support/tickets' 201 -Token $Token -Body $supportBody
$supportTicket = Get-Json $r
if ([string]$supportTicket.delivery_status -ne 'not_configured') { throw "Expected not_configured support delivery status" }
$null = Invoke-Case 'support invalid channel' 'POST' '/api/v1/support/tickets' 400 -Token $Token -Body (@{channel='email';message='invalid'}|ConvertTo-Json -Compress)

$null = Invoke-Case 'list projects' 'GET' '/api/v1/projects' 200 -Token $Token
$projectBody = @{name="Full API Test $Suffix";address='Bishkek';budget_amount=250000;currency='KGS'} | ConvertTo-Json -Compress
$r = Invoke-Case 'create project' 'POST' '/api/v1/projects' 201 -Token $Token -Body $projectBody
$j = Get-Json $r
$ProjectId = [string]$j.id
$null = Invoke-Case 'get project' 'GET' "/api/v1/projects/$ProjectId" 200 -Token $Token
$null = Invoke-Case 'update project' 'PATCH' "/api/v1/projects/$ProjectId" 200 -Token $Token -Body (@{name="Full API Test Updated $Suffix";address='Bishkek';status='active'}|ConvertTo-Json -Compress)
$r = Invoke-Case 'create project with cover' 'POST' '/api/v1/projects/create-with-cover' 201 -Token $Token -Forms @("name=Cover Test $Suffix",'address=Bishkek','budget_amount=50000','currency=KGS',"cover=@$CoverPath;type=image/png")
$j = Get-Json $r
$CoverProjectId = [string]$j.id
$null = Invoke-Case 'archive cover project' 'DELETE' "/api/v1/projects/$CoverProjectId" 200 -Token $Token

$null = Invoke-Case 'list project members' 'GET' "/api/v1/project-members?project_id=$ProjectId" 200 -Token $Token
$inviteBody = @{project_id=$ProjectId;phone=$MemberPhone;role='worker'} | ConvertTo-Json -Compress
$r = Invoke-Case 'create project invite' 'POST' '/api/v1/project-invites' 201 -Token $Token -Body $inviteBody
$memberCodeResponse = Invoke-Case 'member sms request' 'POST' '/api/v1/auth/sms/request' 202 -Body (@{phone=$MemberPhone;name='API test member'}|ConvertTo-Json -Compress)
$memberCode = [string](Get-Json $memberCodeResponse).dev_code
$null = Invoke-Case 'member sms request rate limit' 'POST' '/api/v1/auth/sms/request' 429 -Body (@{phone=$MemberPhone}|ConvertTo-Json -Compress)
$r = Invoke-Case 'member sms verify' 'POST' '/api/v1/auth/sms/verify' 200 -Body (@{phone=$MemberPhone;code=$memberCode}|ConvertTo-Json -Compress)
$j = Get-Json $r
$MemberId = [string]$j.user_id
$null = Invoke-Case 'update project member role' 'PATCH' "/api/v1/project-members/${MemberId}?project_id=${ProjectId}" 200 -Token $Token -Body (@{role='viewer'}|ConvertTo-Json -Compress)
$null = Invoke-Case 'delete project member' 'DELETE' "/api/v1/project-members/${MemberId}?project_id=${ProjectId}" 200 -Token $Token
$null = Invoke-Case 'accept invalid invite' 'POST' '/api/v1/project-invites/accept' 401 -Token $Token -Body (@{invite_token='invalid-token'}|ConvertTo-Json -Compress)

$null = Invoke-Case 'list cost items' 'GET' "/api/v1/cost-items?project_id=$ProjectId" 200 -Token $Token
$costBody = @{project_id=$ProjectId;title='Cement';amount=1200;category='materials';currency='KGS';vendor='Local supplier'} | ConvertTo-Json -Compress
$r = Invoke-Case 'create cost item' 'POST' '/api/v1/cost-items' 201 -Token $Token -Body $costBody
$j = Get-Json $r
$CostId = [string]$j.id
$null = Invoke-Case 'get cost item' 'GET' "/api/v1/cost-items/$CostId" 200 -Token $Token
$null = Invoke-Case 'update cost item' 'PATCH' "/api/v1/cost-items/$CostId" 200 -Token $Token -Body (@{title='Cement bags';amount=1300;category='materials';currency='KGS';vendor='Local supplier'}|ConvertTo-Json -Compress)
$null = Invoke-Case 'delete cost item' 'DELETE' "/api/v1/cost-items/$CostId" 200 -Token $Token

$null = Invoke-Case 'list daily reports' 'GET' "/api/v1/daily-reports?project_id=$ProjectId" 200 -Token $Token
$reportBody = @{project_id=$ProjectId;summary='Foundation works completed';workers_count=4;issues=''} | ConvertTo-Json -Compress
$r = Invoke-Case 'create daily report' 'POST' '/api/v1/daily-reports' 201 -Token $Token -Body $reportBody
$j = Get-Json $r
$ReportId = [string]$j.id
$null = Invoke-Case 'get daily report' 'GET' "/api/v1/daily-reports/$ReportId" 200 -Token $Token
$null = Invoke-Case 'update daily report' 'PATCH' "/api/v1/daily-reports/$ReportId" 200 -Token $Token -Body (@{summary='Foundation works completed and cleaned';workers_count=5;issues=''}|ConvertTo-Json -Compress)
$null = Invoke-Case 'delete daily report' 'DELETE' "/api/v1/daily-reports/$ReportId" 200 -Token $Token

$null = Invoke-Case 'list files' 'GET' "/api/v1/files?project_id=$ProjectId" 200 -Token $Token
$metaBody = @{project_id=$ProjectId;kind='document';original_name='metadata.pdf';storage_path="metadata/$Suffix.pdf";content_type='application/pdf';size_bytes=12} | ConvertTo-Json -Compress
$r = Invoke-Case 'create file metadata' 'POST' '/api/v1/files' 201 -Token $Token -Body $metaBody
$j = Get-Json $r
$MetaFileId = [string]$j.id
$r = Invoke-Case 'upload file' 'POST' '/api/v1/files/upload' 201 -Token $Token -Forms @("project_id=$ProjectId",'kind=photo',"file=@$CoverPath;type=image/png")
$j = Get-Json $r
$UploadFileId = [string]$j.id
$DownloadPath = "F:\Users\kosho\Documents\OnlineProrab_Test\downloaded_$Suffix.png"
$null = Invoke-Case 'download file' 'GET' "/api/v1/files/download?file_id=$UploadFileId" 200 -Token $Token -OutFile $DownloadPath
$null = Invoke-Case 'delete uploaded file' 'DELETE' "/api/v1/files/${UploadFileId}?project_id=${ProjectId}" 200 -Token $Token
$null = Invoke-Case 'delete metadata file' 'DELETE' "/api/v1/files/${MetaFileId}?project_id=${ProjectId}" 200 -Token $Token

$null = Invoke-Case 'list tasks' 'GET' "/api/v1/tasks?project_id=$ProjectId" 200 -Token $Token
$taskBody = @{project_id=$ProjectId;title='Buy cement';description='Call supplier and confirm delivery';status='open'} | ConvertTo-Json -Compress
$r = Invoke-Case 'create task' 'POST' '/api/v1/tasks' 201 -Token $Token -Body $taskBody
$j = Get-Json $r
$TaskId = [string]$j.id
$null = Invoke-Case 'update task' 'PATCH' "/api/v1/tasks/$TaskId" 200 -Token $Token -Body (@{title='Buy cement';description='Delivery confirmed';status='done'}|ConvertTo-Json -Compress)
$null = Invoke-Case 'delete task' 'DELETE' "/api/v1/tasks/${TaskId}?project_id=${ProjectId}" 200 -Token $Token

$null = Invoke-Case 'list audit logs' 'GET' "/api/v1/audit-logs?project_id=$ProjectId" 200 -Token $Token
$null = Invoke-Case 'list subscription plans' 'GET' '/api/v1/subscriptions/plans' 200
$null = Invoke-Case 'subscription status' 'GET' '/api/v1/subscriptions/status' 200 -Token $Token

$null = Invoke-Case 'missing cost item' 'GET' '/api/v1/cost-items/00000000-0000-0000-0000-000000000000' 403 -Token $Token
$null = Invoke-Case 'files missing project query' 'GET' '/api/v1/files' 400 -Token $Token
$null = Invoke-Case 'download missing file id' 'GET' '/api/v1/files/download' 400 -Token $Token
$null = Invoke-Case 'missing daily report' 'GET' '/api/v1/daily-reports/00000000-0000-0000-0000-000000000000' 403 -Token $Token
$null = Invoke-Case 'missing task' 'GET' '/api/v1/tasks/00000000-0000-0000-0000-000000000000' 405 -Token $Token
$null = Invoke-Case 'projects bad method' 'PUT' '/api/v1/projects' 405 -Token $Token
$null = Invoke-Case 'cost items bad method' 'PUT' '/api/v1/cost-items' 405 -Token $Token
$null = Invoke-Case 'tasks bad method' 'PUT' '/api/v1/tasks' 405 -Token $Token
$null = Invoke-Case 'files bad method' 'PUT' '/api/v1/files' 405 -Token $Token
$null = Invoke-Case 'subscriptions status bad method' 'POST' '/api/v1/subscriptions/status' 405 -Token $Token
$null = Invoke-Case 'project members missing query' 'GET' '/api/v1/project-members' 400 -Token $Token
$null = Invoke-Case 'audit missing project query' 'GET' '/api/v1/audit-logs' 400 -Token $Token

$passed = @($Results | Where-Object Passed).Count
$failed = @($Results | Where-Object { -not $_.Passed }).Count
Write-Host ("REQUEST_COVERAGE total={0} passed={1} failed={2} percent={3:N2}" -f $Results.Count,$passed,$failed,(100*$passed/$Results.Count))
Write-Host ("PROJECT_ID=$ProjectId")
Write-Host ("OWNER_ID=$OwnerId")
Write-Host ("MEMBER_ID=$MemberId")
if ($failed -gt 0) { exit 1 }
