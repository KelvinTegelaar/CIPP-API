function Add-CIPPWin32LobAppContent {
    <#
    .SYNOPSIS
        Uploads intunewin file content to a Win32Lob app in Intune.

    .DESCRIPTION
        This function handles the complete process of uploading an intunewin file to a Win32Lob app:
        1. Creates a content version file entry
        2. Waits for Azure Storage URI
        3. Uploads the file to Azure Storage in chunks
        4. Commits the file with encryption info
        5. Finalizes the content version

    .PARAMETER AppId
        The ID of the Win32Lob app to upload content to.

    .PARAMETER FilePath
        Path to the intunewin file to upload.

    .PARAMETER FileName
        Name of the file (from XML metadata).

    .PARAMETER UnencryptedSize
        Unencrypted size of the file (from XML metadata).

    .PARAMETER EncryptionInfo
        Hashtable containing encryption information from XML:
        - EncryptionKey
        - MacKey
        - InitializationVector
        - Mac
        - ProfileIdentifier
        - FileDigest
        - FileDigestAlgorithm

    .PARAMETER TenantFilter
        Tenant ID or domain name for the Graph API call.

    .PARAMETER APIName
        API name for logging (optional).

    .PARAMETER Headers
        Request headers for logging (optional).

    .EXAMPLE
        $EncryptionInfo = @{
            EncryptionKey = '...'
            MacKey = '...'
            InitializationVector = '...'
            Mac = '...'
            ProfileIdentifier = 'ProfileVersion1'
            FileDigest = '...'
            FileDigestAlgorithm = 'SHA256'
        }
        Add-CIPPWin32LobAppContent -AppId '12345' -FilePath 'C:\app.intunewin' -FileName 'app.intunewin' -UnencryptedSize 1024000 -EncryptionInfo $EncryptionInfo -TenantFilter 'contoso.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [int64]$UnencryptedSize,

        [Parameter(Mandatory = $true)]
        [hashtable]$EncryptionInfo,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'AppUpload',

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers
    )

    $BaseUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    $FileInfo = Get-Item $FilePath

    # Create content version file entry
    $ContentBody = ConvertTo-Json @{
        name          = $FileName
        size          = $UnencryptedSize
        sizeEncrypted = [int64]$FileInfo.Length
    }

    $ContentReq = New-GraphPostRequest -Uri "$BaseUri/$AppId/microsoft.graph.win32lobapp/contentVersions/1/files/" -Body $ContentBody -Type POST -tenantid $TenantFilter

    # Wait for Azure Storage URI
    do {
        $AzFileUri = New-GraphGetRequest -Uri "$BaseUri/$AppId/microsoft.graph.win32lobapp/contentVersions/1/files/$($ContentReq.id)" -tenantid $TenantFilter
        if ($AzFileUri.uploadState -like '*fail*') {
            throw "Failed to get Azure Storage URI. Upload state: $($AzFileUri.uploadState)"
        }
        Start-Sleep -Milliseconds 300
    } while ($null -eq $AzFileUri.AzureStorageUri)

    if ($Headers) {
        Write-LogMessage -Headers $Headers -API $APIName -message "Uploading file to $($AzFileUri.azureStorageUri)" -Sev 'Info' -tenant $TenantFilter
    } else {
        Write-Host "Uploading file to $($AzFileUri.azureStorageUri)"
    }

    # Upload file to Azure Storage in chunks
    $chunkSizeInBytes = 4mb
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($FileInfo.FullName)
    $chunks = [Math]::Ceiling($bytes.Length / $chunkSizeInBytes)
    $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunks.ToString('0000')))
    # For anyone that reads this, The maximum chunk size is 100MB for blob storage, so we can upload it as one part and just give it the single ID. Easy :)
    $null = Invoke-RestMethod -Uri "$($AzFileUri.azureStorageUri)&comp=block&blockid=$id" -Method Put -Headers @{'x-ms-blob-type' = 'BlockBlob' } -InFile $FilePath -ContentType 'application/octet-stream'
    $null = Invoke-RestMethod -Uri "$($AzFileUri.azureStorageUri)&comp=blocklist" -Method Put -Body "<?xml version=`"1.0`" encoding=`"utf-8`"?><BlockList><Latest>$id</Latest></BlockList>" -ContentType 'application/xml'

    # Commit the file with encryption info
    $EncBody = @{
        fileEncryptionInfo = @{
            encryptionKey        = $EncryptionInfo.EncryptionKey
            macKey               = $EncryptionInfo.MacKey
            initializationVector = $EncryptionInfo.InitializationVector
            mac                  = $EncryptionInfo.Mac
            profileIdentifier    = $EncryptionInfo.ProfileIdentifier
            fileDigest           = $EncryptionInfo.FileDigest
            fileDigestAlgorithm  = $EncryptionInfo.FileDigestAlgorithm
        }
    } | ConvertTo-Json

    $null = New-GraphPostRequest -Uri "$BaseUri/$AppId/microsoft.graph.win32lobapp/contentVersions/1/files/$($ContentReq.id)/commit" -Body $EncBody -Type POST -tenantid $TenantFilter

    # Wait for commit to complete
    do {
        $CommitStateReq = New-GraphGetRequest -Uri "$BaseUri/$AppId/microsoft.graph.win32lobapp/contentVersions/1/files/$($ContentReq.id)" -tenantid $TenantFilter
        if ($CommitStateReq.uploadState -like '*fail*') {
            $errorMsg = "Commit failed. Upload state: $($CommitStateReq.uploadState)"
            if ($Headers) {
                Write-LogMessage -Headers $Headers -API $APIName -message $errorMsg -Sev 'Warning' -tenant $TenantFilter
            }
            throw $errorMsg
        }
        Start-Sleep -Milliseconds 300
    } while ($CommitStateReq.uploadState -eq 'commitFilePending')

    # Finalize content version
    $null = New-GraphPostRequest -Uri "$BaseUri/$AppId" -tenantid $TenantFilter -Body '{"@odata.type":"#microsoft.graph.win32lobapp","committedContentVersion":"1"}' -type PATCH

    return $true
}
