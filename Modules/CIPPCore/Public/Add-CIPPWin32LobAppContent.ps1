function Add-CIPPWin32LobAppContent {
    <#
    .SYNOPSIS
        Uploads an encrypted .intunewin payload to a Win32 LOB app as a new content version and commits it.
    .DESCRIPTION
        Reads the payload from a local file (bundled MSP/Choco packages) or a CIPP storage blob (uploaded
        packages) in fixed-size blocks and streams them to the app's Azure Storage upload URI, renewing the
        URI while the upload runs. A new content version is created on every call, so the same function
        uploads the first version of a new app and later versions of an existing one.
        Returns the committed content version id.
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true, ParameterSetName = 'File')][string]$FilePath,
        # Path inside CIPP storage, e.g. 'app-packages/<id>/IntunePackage.intunewin'
        [Parameter(Mandatory = $true, ParameterSetName = 'Blob')][string]$BlobPath,
        [Parameter(Mandatory = $true, ParameterSetName = 'Blob')][int64]$EncryptedSize,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][int64]$UnencryptedSize,
        [Parameter(Mandatory = $true)][hashtable]$EncryptionInfo,
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$APIName = 'AppUpload',
        [hashtable]$Headers,
        # Extra app properties sent with the committedContentVersion PATCH (largeIcon, displayVersion, ...)
        [hashtable]$AppProperties,
        [int]$ChunkSize = 8MB,
        [int]$MaxConcurrency = 4,
        [string]$ConnectionString = $env:AzureWebJobsStorage,
        # The LOB app type the content belongs to (Win32 and macOS packages share the upload flow)
        [ValidateSet('win32LobApp', 'macOSPkgApp', 'macOSDmgApp')][string]$AppType = 'win32LobApp'
    )

    $BaseUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/microsoft.graph.$AppType"
    $Source = if ($PSCmdlet.ParameterSetName -eq 'File') { [System.IO.File]::OpenRead($FilePath) }
    $Size = if ($Source) { $Source.Length } else { $EncryptedSize }

    try {
        $ContentVersion = New-GraphPostRequest -uri "$BaseUri/contentVersions" -tenantid $TenantFilter -type POST -body '{}'
        $FilesUri = "$BaseUri/contentVersions/$($ContentVersion.id)/files"
        $File = New-GraphPostRequest -uri $FilesUri -tenantid $TenantFilter -type POST -body (ConvertTo-Json -Compress -InputObject @{
                '@odata.type' = '#microsoft.graph.mobileAppContentFile'; name = $FileName; size = $UnencryptedSize; sizeEncrypted = $Size; isDependency = $false; manifest = $null
            })
        do {
            Start-Sleep -Seconds 1
            $File = New-GraphGetRequest -uri "$FilesUri/$($File.id)" -tenantid $TenantFilter
        } while ($File.uploadState -eq 'azureStorageUriRequestPending')
        if ($File.uploadState -ne 'azureStorageUriRequestSuccess') { throw "Intune did not issue an upload location: $($File.uploadState)" }
        $UploadUri = $File.azureStorageUri


        $BlockCount = [int][Math]::Ceiling($Size / $ChunkSize)
        $BlockIds = [string[]]@(foreach ($i in 0..($BlockCount - 1)) { [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($i.ToString('000000'))) })
        $LastRenew = $null
        $BlockHeaders = [Collections.Generic.Dictionary[string, string]]::new()
        $BlockHeaders['x-ms-blob-type'] = 'BlockBlob'
        for ($Start = 0; $Start -lt $BlockCount; $Start += $MaxConcurrency) {
            $Batch = [int[]]@($Start..([Math]::Min($Start + $MaxConcurrency, $BlockCount) - 1))

            # The upload URI lives 15 minutes and can only be renewed once a block has landed.
            if ($LastRenew -and $LastRenew.Elapsed.TotalSeconds -gt 420) {
                $null = New-GraphPostRequest -uri "$FilesUri/$($File.id)/renewUpload" -tenantid $TenantFilter -type POST -body '{}'
                do {
                    Start-Sleep -Seconds 2
                    $Renew = New-GraphGetRequest -uri "$FilesUri/$($File.id)" -tenantid $TenantFilter
                } while ($Renew.uploadState -eq 'azureStorageUriRenewalPending')
                if ($Renew.uploadState -ne 'azureStorageUriRenewalSuccess') { throw "Intune could not renew the upload location: $($Renew.uploadState)" }
                $UploadUri = $Renew.azureStorageUri
                $LastRenew.Restart()
            }

            $Blocks = [System.Collections.Generic.List[byte[]]]::new()
            if ($Source) {
                foreach ($i in $Batch) {
                    $Buffer = [byte[]]::new([Math]::Min($ChunkSize, $Size - [int64]$i * $ChunkSize))
                    $Source.ReadExactly($Buffer, 0, $Buffer.Length)
                    $Blocks.Add($Buffer)
                }
            } else {
                foreach ($i in $Batch) {
                    $End = [Math]::Min(([int64]$i + 1) * $ChunkSize, $Size) - 1
                    $Blocks.Add((New-CIPPAzStorageRequest -Service blob -Resource $BlobPath -ConnectionString $ConnectionString -ErrorAction Stop -Headers @{ Range = "bytes=$([int64]$i * $ChunkSize)-$End" }).Bytes)
                }
            }

            # Intune's upload SAS uses a stored access policy that can take ~30 s to apply after issue.
            $Pending = [System.Collections.Generic.List[int]]::new([int[]]@(0..($Batch.Count - 1)))
            $Deadline = [Diagnostics.Stopwatch]::StartNew()
            while ($Pending.Count -gt 0) {
                $Puts = foreach ($k in $Pending) {
                    [CIPP.CIPPConcurrentRequest]@{ Uri = "$UploadUri&comp=block&blockid=$([uri]::EscapeDataString($BlockIds[$Batch[$k]]))"; Method = 'PUT'; BodyBytes = $Blocks[$k]; Headers = $BlockHeaders; TimeoutSec = 300 }
                }
                $Results = [CIPP.CIPPRestClient]::SendConcurrent([CIPP.CIPPConcurrentRequest[]]@($Puts), $MaxConcurrency, 3, $global:CraftPipelineStopToken)
                $Retry = [System.Collections.Generic.List[int]]::new()
                foreach ($R in $Results) {
                    if ($R.IsSuccess) { continue }
                    if ($R.StatusCode -eq 403 -and $R.Result.Content -match 'signed identifier' -and $Deadline.Elapsed.TotalSeconds -lt 60) { $Retry.Add($Pending[$R.Index]); continue }
                    throw "Uploading block $($Batch[$Pending[$R.Index]]) failed: $($R.StatusCode) $($R.Error) $($R.Result.Content)"
                }
                $Pending = $Retry
                if ($Pending.Count -gt 0) { Start-Sleep -Seconds 3 }
            }
            $LastRenew ??= [Diagnostics.Stopwatch]::StartNew()
        }

        $BlockList = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($BlockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
        $Commit = [CIPP.CIPPRestClient]::SendConcurrent([CIPP.CIPPConcurrentRequest[]]@([CIPP.CIPPConcurrentRequest]@{ Uri = "$UploadUri&comp=blocklist"; Method = 'PUT'; Body = $BlockList; ContentType = 'application/xml' }), 1, 3, $global:CraftPipelineStopToken)[0]
        if (-not $Commit.IsSuccess) { throw "Committing the uploaded blocks failed: $($Commit.StatusCode) $($Commit.Result.Content)" }

        $null = New-GraphPostRequest -uri "$FilesUri/$($File.id)/commit" -tenantid $TenantFilter -type POST -body (ConvertTo-Json -Compress -InputObject @{
                fileEncryptionInfo = @{
                    encryptionKey        = $EncryptionInfo.EncryptionKey
                    macKey               = $EncryptionInfo.MacKey
                    initializationVector = $EncryptionInfo.InitializationVector
                    mac                  = $EncryptionInfo.Mac
                    profileIdentifier    = $EncryptionInfo.ProfileIdentifier
                    fileDigest           = $EncryptionInfo.FileDigest
                    fileDigestAlgorithm  = $EncryptionInfo.FileDigestAlgorithm
                }
            })
        do {
            Start-Sleep -Seconds 2
            $File = New-GraphGetRequest -uri "$FilesUri/$($File.id)" -tenantid $TenantFilter
        } while ($File.uploadState -eq 'commitFilePending')
        if ($File.uploadState -ne 'commitFileSuccess') {
            $Message = "Intune rejected the uploaded package: $($File.uploadState)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error
            throw $Message
        }
        # Committing a version PATCHes the app; properties left out (largeIcon) are cleared, so callers resend them here.
        $AppPatch = @{ '@odata.type' = "#microsoft.graph.$AppType"; committedContentVersion = "$($ContentVersion.id)" }
        if ($AppProperties) { foreach ($Key in $AppProperties.Keys) { $AppPatch[$Key] = $AppProperties[$Key] } }
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -Depth 10 -Compress -InputObject $AppPatch)
        return $ContentVersion.id
    } finally {
        if ($Source) { $Source.Dispose() }
    }
}
