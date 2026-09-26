function New-CIPPReportAttachmentLink {
    <#
    .SYNOPSIS
        Upload an email attachment to blob storage and return a read-only SAS download URL
    .DESCRIPTION
        Used when an attachment is too large for Graph sendMail's 4MB request limit. The blob is recorded
        in the ReportAttachmentBlobs table so Start-ReportAttachmentRetentionCleanup can delete it once the
        report attachment retention period passes; the SAS link expires at the same time.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ContentBytes,
        [string]$ContentType = 'application/octet-stream',
        [string]$ConnectionString = $env:AzureWebJobsStorage
    )

    $ContainerName = 'report-attachments'
    $ConfigTable = Get-CIPPTable -TableName Config
    $RetentionSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'ReportAttachmentRetention' and RowKey eq 'Settings'"
    $RetentionDays = if ($RetentionSettings.RetentionDays) { [int]$RetentionSettings.RetentionDays } else { 360 }

    $Containers = try { New-CIPPAzStorageRequest -Service 'blob' -Component 'list' -ConnectionString $ConnectionString } catch { @() }
    if (-not ($Containers | Where-Object { $_.Name -eq $ContainerName })) {
        $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $ContainerName -Method 'PUT' -QueryParams @{ restype = 'container' } -ConnectionString $ConnectionString
    }

    $SafeName = $Name -replace '[^a-zA-Z0-9_.\-]', '_'
    $BlobId = [string][guid]::NewGuid()
    $BlobPath = "$ContainerName/$BlobId/$SafeName"
    $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $BlobPath -Method 'PUT' -ContentType $ContentType -Body ([Convert]::FromBase64String($ContentBytes)) -ConnectionString $ConnectionString

    $AttachmentTable = Get-CIPPTable -TableName 'ReportAttachmentBlobs'
    Add-CIPPAzDataTableEntity @AttachmentTable -Force -Entity @{
        PartitionKey = 'ReportAttachment'
        RowKey       = $BlobId
        BlobPath     = $BlobPath
        FileName     = $SafeName
    }

    $Conn = @{}
    foreach ($Part in ($ConnectionString -split ';')) {
        if ($Part.Trim() -match '^(.+?)=(.+)$') { $Conn[$matches[1]] = $matches[2] }
    }
    $Sas = New-CIPPAzServiceSAS -AccountName $Conn['AccountName'] -AccountKey $Conn['AccountKey'] -Service 'blob' -SignedResource 'b' -ResourcePath $BlobPath `
        -Permissions 'r' -ExpiryTime ([DateTime]::UtcNow.AddDays($RetentionDays)) -ContentDisposition "attachment; filename=`"$SafeName`"" -ConnectionString $ConnectionString

    return $Sas.ResourceUri + $Sas.Token
}
