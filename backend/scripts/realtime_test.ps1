$ErrorActionPreference = 'Stop'
$Base = 'http://localhost:8080'
$Suffix = (Get-Date -Format 'HHmmssfff')
$Phone = "+996703$Suffix"

function JsonBody($value) {
  return ($value | ConvertTo-Json -Compress)
}

function Start-SSEJob($uri, $token) {
  $script = {
    param($StreamUri, $AccessToken)
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $StreamUri)
    $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $AccessToken)
    $request.Headers.Accept.ParseAdd('text/event-stream')
    try {
      $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
      if ([int]$response.StatusCode -ne 200) {
        throw "SSE status $([int]$response.StatusCode)"
      }
      Write-Output 'READY'
      $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
      $reader = [System.IO.StreamReader]::new($stream)
      $data = ''
      while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line.StartsWith('data:')) {
          $data += $line.Substring(5).TrimStart()
        } elseif ([string]::IsNullOrEmpty($line) -and $data) {
          Write-Output ("EVENT:" + $data)
          $data = ''
          break
        }
      }
    } finally {
      if ($reader) { $reader.Dispose() }
      if ($response) { $response.Dispose() }
      $request.Dispose()
      $client.Dispose()
    }
  }
  return Start-Job -ScriptBlock $script -ArgumentList $uri,$token
}

$auth = Invoke-RestMethod -Method Post -Uri "$Base/api/v1/auth/sms/request" -ContentType 'application/json' -Body (JsonBody @{phone=$Phone;name='Realtime test'})
$verified = Invoke-RestMethod -Method Post -Uri "$Base/api/v1/auth/sms/verify" -ContentType 'application/json' -Body (JsonBody @{phone=$Phone;code=$auth.dev_code})
$Token = [string]$verified.access_token
$project = Invoke-RestMethod -Method Post -Uri "$Base/api/v1/projects" -Headers @{Authorization="Bearer $Token"} -ContentType 'application/json' -Body (JsonBody @{name="Realtime $Suffix";address='Bishkek';start_date='2026-09-07';budget_amount=10000;currency='KGS'})
$ProjectId = [string]$project.id

$globalJob = Start-SSEJob "$Base/api/v1/realtime" $Token
$projectJob = Start-SSEJob "$Base/api/v1/realtime?project_id=$ProjectId" $Token
$jobs = @($globalJob,$projectJob)
$ready = @{}
$readyDeadline = (Get-Date).AddSeconds(15)
while ($ready.Count -lt 2 -and (Get-Date) -lt $readyDeadline) {
  foreach ($job in $jobs) {
    $output = @(Receive-Job -Job $job -Keep)
    if ($output -contains 'READY') { $ready[$job.Id] = $true }
  }
  Start-Sleep -Milliseconds 100
}
if ($ready.Count -ne 2) {
  $diagnostic = ($jobs | ForEach-Object { Receive-Job -Job $_ -Keep } | Out-String)
  $jobs | Stop-Job -ErrorAction SilentlyContinue
  $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
  throw "SSE subscribers were not ready: $diagnostic"
}

$cost = Invoke-RestMethod -Method Post -Uri "$Base/api/v1/cost-items" -Headers @{Authorization="Bearer $Token"} -ContentType 'application/json' -Body (JsonBody @{project_id=$ProjectId;title="Realtime cement $Suffix";amount=321;category='materials';currency='KGS';vendor='sync-test';spent_at='2026-09-07'})
$CostId = [string]$cost.id
$events = @{}
$eventDeadline = (Get-Date).AddSeconds(15)
while ($events.Count -lt 2 -and (Get-Date) -lt $eventDeadline) {
  foreach ($job in $jobs) {
    $output = @(Receive-Job -Job $job -Keep)
    foreach ($line in $output) {
      if ([string]$line -like 'EVENT:*') {
        $events[$job.Id] = ([string]$line).Substring(6) | ConvertFrom-Json
      }
    }
  }
  Start-Sleep -Milliseconds 100
}
$jobs | Stop-Job -ErrorAction SilentlyContinue
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue
if ($events.Count -ne 2) { throw "Expected 2 realtime events, received $($events.Count)" }
foreach ($event in $events.Values) {
  if ($event.project_id -ne $ProjectId) { throw 'Wrong project_id in realtime event' }
  if ($event.entity_type -ne 'cost_item') { throw 'Wrong entity_type in realtime event' }
  if ($event.entity_id -ne $CostId) { throw 'Wrong entity_id in realtime event' }
  if ($event.action -ne 'created') { throw 'Wrong action in realtime event' }
}
$list = Invoke-RestMethod -Method Get -Uri "$Base/api/v1/cost-items?project_id=$ProjectId" -Headers @{Authorization="Bearer $Token"}
$found = @($list | Where-Object { $_.id -eq $CostId })
if ($found.Count -ne 1) { throw 'Created cost was not persisted' }
Invoke-RestMethod -Method Delete -Uri "$Base/api/v1/projects/$ProjectId" -Headers @{Authorization="Bearer $Token"} | Out-Null
Write-Host "REALTIME_SUCCESS subscribers=2 events=2 project=$ProjectId cost=$CostId"
