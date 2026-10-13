[CmdletBinding()]
param(
  [string]$DnsName = "app.plsdc.internal",
  [string]$OutputDirectory = "certificates",
  [ValidateRange(1, 10)]
  [int]$ValidYears = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
  throw "New-SelfSignedCertificate is unavailable. Run this script on Windows with the PKI module."
}

$outputPath = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
  $OutputDirectory
}
else {
  Join-Path $PSScriptRoot $OutputDirectory
}

$outputPath = [IO.Path]::GetFullPath($outputPath)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$pfxPassword = Read-Host "Enter a password for the Application Gateway PFX" -AsSecureString
$rootCertificate = $null
$serverCertificate = $null

function Export-PemCertificate {
  param(
    [Parameter(Mandatory)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
    [Parameter(Mandatory)]
    [string]$Path
  )

  $base64 = [Convert]::ToBase64String(
    $Certificate.RawData,
    [Base64FormattingOptions]::InsertLineBreaks
  )
  $pem = "-----BEGIN CERTIFICATE-----`r`n$base64`r`n-----END CERTIFICATE-----`r`n"
  [IO.File]::WriteAllText($Path, $pem, [Text.Encoding]::ASCII)
}

try {
  $rootCertificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=PLSDC Lab Root CA" `
    -KeyAlgorithm RSA `
    -KeyLength 4096 `
    -HashAlgorithm SHA256 `
    -KeyUsage CertSign, CRLSign, DigitalSignature `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears($ValidYears) `
    -TextExtension @("2.5.29.19={critical}{text}ca=1&pathlength=0")

  $serverCertificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=$DnsName" `
    -DnsName $DnsName `
    -Signer $rootCertificate `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears($ValidYears) `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

  $pfxPath = Join-Path $outputPath "$DnsName.pfx"
  $pfxBase64Path = Join-Path $outputPath "$DnsName.pfx.base64"
  $rootCaPath = Join-Path $outputPath "plsdc-lab-root-ca.crt"

  Export-PfxCertificate `
    -Cert $serverCertificate `
    -FilePath $pfxPath `
    -Password $pfxPassword `
    -ChainOption EndEntityCertOnly `
    -Force | Out-Null

  Export-PemCertificate -Certificate $rootCertificate -Path $rootCaPath

  $pfxBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))
  [IO.File]::WriteAllText($pfxBase64Path, $pfxBase64, [Text.Encoding]::ASCII)

  Write-Host ""
  Write-Host "Created:"
  Write-Host "  Application Gateway PFX: $pfxPath"
  Write-Host "  Terraform Base64 value:  $pfxBase64Path"
  Write-Host "  Consumer trusted root CA: $rootCaPath"
  Write-Host ""
  Write-Host "Use the same PFX password for tls_certificate_password in provider\terraform.tfvars."
}
finally {
  if ($serverCertificate) {
    Remove-Item "Cert:\CurrentUser\My\$($serverCertificate.Thumbprint)" -Force -ErrorAction SilentlyContinue
  }
  if ($rootCertificate) {
    Remove-Item "Cert:\CurrentUser\My\$($rootCertificate.Thumbprint)" -Force -ErrorAction SilentlyContinue
  }
}
