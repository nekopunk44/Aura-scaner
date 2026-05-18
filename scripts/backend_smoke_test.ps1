$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $repoRoot 'backend'
$uploadFile = Join-Path $backendRoot 'smoke_test_upload.txt'
$downloadFile = Join-Path $backendRoot 'smoke_test_download.txt'

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$email = "codex_$ts@example.com"
$password = 'secret123'
$name = 'Codex Smoke'

Set-Content -Path $uploadFile -Value "smoke test $ts" -Encoding UTF8

$process = Start-Process node -ArgumentList 'dist/app.js' -WorkingDirectory $backendRoot -PassThru -WindowStyle Hidden

try {
    Start-Sleep -Seconds 4

    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health' -Method Get

    $registerBody = @{
        email = $email
        password = $password
        name = $name
    } | ConvertTo-Json

    $register = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/api/auth/register' -Method Post -ContentType 'application/json' -Body $registerBody
    $token = $register.token
    $headers = @{ Authorization = "Bearer $token" }

    $listBefore = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/api/documents' -Headers $headers -Method Get

    $uploadRaw = & curl.exe -s -X POST 'http://127.0.0.1:3000/api/documents/upload' `
        -H "Authorization: Bearer $token" `
        -F "file=@$uploadFile;type=text/plain" `
        -F "name=Smoke Upload"
    $upload = $uploadRaw | ConvertFrom-Json

    $listAfterUpload = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/api/documents' -Headers $headers -Method Get

    $renameBody = @{ name = 'Renamed Smoke Upload' } | ConvertTo-Json
    $renamed = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/documents/$($upload._id)" -Headers $headers -Method Patch -ContentType 'application/json' -Body $renameBody

    Invoke-WebRequest -Uri "http://127.0.0.1:3000/api/documents/$($upload._id)/download" -Headers $headers -OutFile $downloadFile | Out-Null

    $delete = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/documents/$($upload._id)" -Headers $headers -Method Delete
    $listAfterDelete = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/api/documents' -Headers $headers -Method Get

    [pscustomobject]@{
        health = $health.status
        registeredEmail = $register.user.email
        initialCount = @($listBefore).Count
        uploadedName = $upload.name
        uploadedFormat = $upload.format
        afterUploadCount = @($listAfterUpload).Count
        renamedTo = $renamed.name
        downloadExists = Test-Path $downloadFile
        downloadSize = (Get-Item $downloadFile).Length
        deleteMessage = $delete.message
        finalCount = @($listAfterDelete).Count
    } | Format-List
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }

    Remove-Item $uploadFile -ErrorAction SilentlyContinue
    Remove-Item $downloadFile -ErrorAction SilentlyContinue
}
