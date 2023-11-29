param($name)
$Table = Get-CippTable -tablename 'apps'
$Filter = "PartitionKey eq 'apps' and RowKey eq '$name'" 
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$ChocoApp = (Get-CIPPAzDataTableEntity @Table -filter $Filter).JSON | ConvertFrom-Json
$intuneBody = $ChocoApp.IntuneBody
$tenants = if ($chocoapp.Tenant -eq 'AllTenants') { 
    (Get-tenants).defaultDomainName
} else {
    $chocoapp.Tenant
} 
if ($chocoApp.type -eq 'MSPApp') {
    [xml]$Intunexml = Get-Content "AddMSPApp\$($ChocoApp.MSPAppName).app.xml"
    $intunewinFilesize = (Get-Item "AddMSPApp\$($ChocoApp.MSPAppName).intunewin")
    $Infile = "AddMSPApp\$($ChocoApp.MSPAppName).intunewin"
} else {
    [xml]$Intunexml = Get-Content 'AddChocoApp\choco.app.xml'
    $intunewinFilesize = (Get-Item 'AddChocoApp\IntunePackage.intunewin')
    $Infile = "AddChocoApp\$($intunexml.ApplicationInfo.FileName)"
}
$assignTo = $ChocoApp.AssignTo
$AssignToIntent = $ChocoApp.InstallationIntent
$Baseuri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
$ContentBody = ConvertTo-Json @{
    name          = $intunexml.ApplicationInfo.FileName
    size          = [int64]$intunexml.ApplicationInfo.UnencryptedContentSize
    sizeEncrypted = [int64]($intunewinFilesize).length
} 
$ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter
$RemoveCacheFile = if ($chocoapp.Tenant -ne 'AllTenants') {
    Remove-AzDataTableEntity @Table -Entity $clearRow
} else {
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$($ChocoApp | ConvertTo-Json)"
        RowKey       = "$($ClearRow.RowKey)"
        PartitionKey = 'apps'
        status       = 'Deployed'
    }
}
$EncBody = @{
    fileEncryptionInfo = @{
        encryptionKey        = $intunexml.ApplicationInfo.EncryptionInfo.EncryptionKey
        macKey               = $intunexml.ApplicationInfo.EncryptionInfo.MacKey
        initializationVector = $intunexml.ApplicationInfo.EncryptionInfo.InitializationVector
        mac                  = $intunexml.ApplicationInfo.EncryptionInfo.Mac
        profileIdentifier    = $intunexml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
        fileDigest           = $intunexml.ApplicationInfo.EncryptionInfo.FileDigest
        fileDigestAlgorithm  = $intunexml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
    }
} | ConvertTo-Json

foreach ($tenant in $tenants) {
    Try {

        $ApplicationList = (New-graphGetRequest -Uri $baseuri -tenantid $Tenant) | Where-Object { $_.DisplayName -eq $ChocoApp.ApplicationName }
        if ($ApplicationList.displayname.count -ge 1) { 
            Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message "$($ChocoApp.ApplicationName) exists. Skipping this application" -Sev 'Info'
            continue
        }
        if ($chocoApp.type -eq 'WinGet') { 
            Write-Host 'Winget!'
            Write-Host ($intuneBody | ConvertTo-Json -Compress)
            $NewApp = New-GraphPostRequest -Uri $baseuri -Body ($intuneBody | ConvertTo-Json -Compress) -Type POST -tenantid $tenant
            Start-Sleep -Milliseconds 200
            Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message "$($ChocoApp.ApplicationName) uploaded as WinGet app." -Sev 'Info'
            if ($AssignTo -ne 'On') {
                $intent = if ($AssignToIntent) { 'Uninstall' } else { 'Required' }
                Set-CIPPAssignedApplication -ApplicationId $NewApp.Id -Intent $intent -TenantFilter $tenant -groupName "$AssignTo" -AppType 'WinGet'
            }
            Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message "$($ChocoApp.ApplicationName) Successfully created" -Sev 'Info'
            exit 0
        } else {
            $NewApp = New-GraphPostRequest -Uri $baseuri -Body ($intuneBody | ConvertTo-Json) -Type POST -tenantid $tenant

        }
        $ContentReq = New-GraphPostRequest -Uri "$($BaseURI)/$($NewApp.id)/microsoft.graph.win32lobapp/contentVersions/1/files/" -Body $ContentBody -Type POST -tenantid $tenant
        do {
            $AzFileUri = New-graphGetRequest -Uri "$($BaseURI)/$($NewApp.id)/microsoft.graph.win32lobapp/contentVersions/1/files/$($ContentReq.id)" -tenantid $tenant
            if ($AZfileuri.uploadState -like '*fail*') { break }
            Start-Sleep -Milliseconds 300
        } while ($AzFileUri.AzureStorageUri -eq $null) 
        
        $chunkSizeInBytes = 4mb
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($($intunewinFilesize.fullname))
        $chunks = [Math]::Ceiling($bytes.Length / $chunkSizeInBytes)
        $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunks.ToString('0000')))
        #For anyone that reads this, The maximum chunk size is 100MB for blob storage, so we can upload it as one part and just give it the single ID. Easy :)
        $Upload = Invoke-RestMethod -Uri "$($AzFileUri.azureStorageUri)&comp=block&blockid=$id" -Method Put -Headers @{'x-ms-blob-type' = 'BlockBlob' } -InFile $inFile -ContentType 'application/octet-stream'
        $ConfirmUpload = Invoke-RestMethod -Uri "$($AzFileUri.azureStorageUri)&comp=blocklist" -Method Put -Body "<?xml version=`"1.0`" encoding=`"utf-8`"?><BlockList><Latest>$id</Latest></BlockList>"
        $CommitReq = New-graphPostRequest -Uri "$($BaseURI)/$($NewApp.id)/microsoft.graph.win32lobapp/contentVersions/1/files/$($ContentReq.id)/commit" -Body $EncBody -Type POST -tenantid $tenant
         
        do {
            $CommitStateReq = New-graphGetRequest -Uri "$($BaseURI)/$($NewApp.id)/microsoft.graph.win32lobapp/contentVersions/1/files/$($ContentReq.id)" -tenantid $tenant
            if ($CommitStateReq.uploadState -like '*fail*') {
                Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message "$($ChocoApp.ApplicationName) Commit failed. Please check if app uploaded succesful" -Sev 'Warning'
                break 
            }
            Start-Sleep -Milliseconds 300
        } while ($CommitStateReq.uploadState -eq 'commitFilePending')        
        $CommitFinalizeReq = New-graphPostRequest -Uri "$($BaseURI)/$($NewApp.id)" -tenantid $tenant -Body '{"@odata.type":"#microsoft.graph.win32lobapp","committedContentVersion":"1"}' -type PATCH
        Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message "Added Application $($chocoApp.ApplicationName)" -Sev 'Info'
        if ($AssignTo -ne 'On') {
            $intent = if ($AssignToIntent) { 'Uninstall' } else { 'Required' }
            Set-CIPPAssignedApplication -ApplicationId $NewApp.Id -Intent $intent -TenantFilter $tenant -groupName "$AssignTo" -AppType 'Win32Lob'

        }
        Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message 'Successfully added Application' -Sev 'Info'
    } catch {
        "Failed to add Application for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -api 'AppUpload' -tenant $($Tenant) -message "Failed adding Application $($ChocoApp.ApplicationName). Error: $($_.Exception.Message)" -Sev 'Error'
        continue
    }

}