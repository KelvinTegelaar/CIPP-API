if (!(Get-Module -ListAvailable AzTable)) {
    Install-Module AzTable -Confirm:$false -Force
}
$Logo = @'
   _____ _____ _____  _____  
  / ____|_   _|  __ \|  __ \ 
 | |      | | | |__) | |__) |
 | |      | | |  ___/|  ___/ 
 | |____ _| |_| |    | |     
  \_____|_____|_|    |_|     
                
'@
Write-Host $Logo
Write-Host '- Connecting to Azure'
Connect-AzAccount -Subscription '##SUBSCRIPTION##'
$RGName = '##RESOURCEGROUP##'
$FunctionApp = '##FUNCTIONAPP##'

$StandardTableCols = @('PartitionKey', 'RowKey', 'TableTimestamp', 'Etag')
$FunctionStorageSettings = @('AzureWebJobsStorage', 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING')

function Start-SleepProgress($Seconds) {
    $doneDT = (Get-Date).AddSeconds($Seconds)
    while ($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity 'Sleeping' -Status 'Sleeping...' -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity 'Sleeping' -Status 'Sleeping...' -SecondsRemaining 0 -Completed
}

if (Get-AzResourceGroup -Name $RGName) {
    Write-Host '- Getting storage account details'
    $StorageAccounts = Get-AzResource -ResourceGroupName $RGName -ResourceType 'Microsoft.Storage/storageAccounts'
    $StorageV1Present = $false
    $StorageV2Present = $false

    foreach ($StorageAccount in $StorageAccounts) {
        switch ($StorageAccount.Kind) {
            'StorageV2' {
                $StorageV2Present = $true 
                $SourceResource = $StorageAccount
            }
            'Storage' { 
                $StorageV1Present = $true
                $DestinationResource = $StorageAccount
            }
        }
    }

    if ($SourceResource) {
        Write-Host '- Source resource exists, getting connection string'
        $saKey = (Get-AzStorageAccountKey -ResourceGroupName $RGName -Name $SourceResource.Name)[0].Value
        $SourceConnectionString = 'DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};EndpointSuffix=core.windows.net' -f $SourceResource.Name, $saKey
        $SourceContext = New-AzStorageContext -ConnectionString $SourceConnectionString
    }

    if ($StorageV2Present -and -not $StorageV1Present) {
        try {
            Write-Host '- Exporting storage resource template'
            Export-AzResourceGroup -ResourceGroupName $RGName -Resource $SourceResource.ResourceId
            $Template = Get-Content -Path .\$RGName.json | ConvertFrom-Json
            Remove-Item .\$RGName.json

            # Convert type to Storage and remove accessTier property
            $Template.resources[0].kind = 'Storage'
            $Template.resources[0].properties = $Template.resources[0].properties | Select-Object minimumTlsVersion, allowBlobPublicAccess, networkAcls, supportsHttpsTrafficOnly, encryption

            $DestResourceNameProp = $Template.parameters.psobject.properties.name
            $DestResourceName = '{0}v1' -f $SourceResource.Name
            $Parameters = @{
                $DestResourceNameProp = $DestResourceName
            }
        
            $Template | ConvertTo-Json -Depth 100 | Out-File .\DestinationStorageTemplate.json

            Write-Host '- Importing V1 storage resource'
            New-AzResourceGroupDeployment -ResourceGroupName $RGName -Name CippStorageMigration -TemplateParameterObject $Parameters -TemplateFile .\DestinationStorageTemplate.json

            $DestinationResource = Get-AzResource -ResourceGroupName $RGName -ResourceName $DestResourceName
        }
        catch {
            Write-Host "Error detected during template deployment, waiting 5 minutes before continuing: $($_.Exception.Message)"
            Start-SleepProgress -Seconds 300
        }
    }

    if ($DestinationResource) {
        Write-Host '- Destination resource exists, getting connection string'
        $Keys = Get-AzStorageAccountKey -ResourceGroupName $RGName -Name $DestinationResource.Name
        if (($Keys | Measure-Object).Count -eq 0) {
            Write-Host 'Creating account key'
            $Keys = New-AzStorageAccountKey -ResourceGroupName $RGName -Name $DestinationResource.Name -KeyName key1
        }
        $saKey = $Keys[0].Value
        $DestinationConnectionString = 'DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};EndpointSuffix=core.windows.net' -f $DestinationResource.Name, $saKey
        $DestinationContext = New-AzStorageContext -ConnectionString $DestinationConnectionString
    }

    if ($SourceContext -and $DestinationContext) {
        Write-Host '- Migrating table data'
        $SourceTables = Get-AzStorageTable -Context $SourceContext | Where-Object { $_.Name -notmatch 'AzureWebJobsHostLogs*' -and $_.Name -notmatch 'History' -and $_.Name -notmatch 'Instances' -and $_.Name -notmatch 'TestHubName' -and $_.Name -ne 'CippLogs' }
        $DestinationTables = Get-AzStorageTable -Context $DestinationContext | Where-Object { $_.Name -notmatch 'AzureWebJobsHostLogs*' -and $_.Name -notmatch 'History' -and $_.Name -notmatch 'Instances' -and $_.Name -notmatch 'TestHubName' -and $_.Name -ne 'CippLogs' }

        foreach ($SourceTable in $SourceTables) {
            Write-Host "`r`nTable: $($SourceTable.Name)"
            $HasProperties = $false
            $DestinationTable = $DestinationTables | Where-Object { $_.Name -eq $SourceTable.Name }
            Write-Host 'Getting Rows'
            $TableRows = Get-AzTableRow -Table $SourceTable.CloudTable
            if (($TableRows | Measure-Object).Count -gt 0) {
                $PropertyNames = $TableRows[0].PSObject.Properties.Name | Where-Object { $_ -notin $StandardTableCols }
                if (($PropertyNames | Measure-Object).Count -gt 0) {
                    $HasProperties = $true
                }
                $RowCount = ($TableRows | Measure-Object).Count
                Write-Host "Rows to migrate: $RowCount"
                foreach ($Row in $TableRows) {
                    $AddRow = @{
                        Table        = $DestinationTable.CloudTable
                        RowKey       = $Row.RowKey
                        PartitionKey = $Row.PartitionKey
                    }
                    if ($HasProperties) {
                        $Property = @{} 
                        foreach ($PropertyName in $PropertyNames) {
                            $Property.$PropertyName = $Row.$PropertyName
                        }
                        $AddRow.Property = $Property
                    }
                    Add-AzTableRow @AddRow -UpdateExisting | Out-Null
                }
            }
            else {
                Write-Host 'No rows to migrate'
            }
        }
    }
    if ($DestinationConnectionString) {
        Write-Host '- Getting function app'

        $Function = Get-AzFunctionApp -ResourceGroupName $RGName -Name $FunctionApp
        $AppSettings = $Function.ApplicationSettings 

        Write-Host 'Backing up settings'
        $AppSettings | ConvertTo-Json | Out-File .\AppSettingsBackup.json -NoClobber

        Write-Host 'Changing connection strings'
        foreach ($StorageSetting in $FunctionStorageSettings) {
            $AppSettings.$StorageSetting = $DestinationConnectionString
        }

        Write-Host 'Removing AzureWebJobsDashboard setting'
        $Function | Remove-AzFunctionAppSetting -AppSettingName AzureWebJobsDashboard -Force

        Write-Host 'Updating function app'
        $Function | Update-AzFunctionAppSetting -AppSetting $AppSettings

        Write-Host 'Restarting function app'
        $Function | Restart-AzFunctionApp

        Write-Host 'Waiting 5 minutes before trying to sync with GitHub'
        Start-SleepProgress -Seconds 300

        Write-Host 'Synchronizing with GitHub'
        & az functionapp deployment source sync --name $FunctionApp --resource-group $RGName

        Write-Host 'Done.`r`n`r`nIMPORTANT NOTE: Please rememeber to delete the StorageV2 resource once you have confirmed that the function app is running as expected.'
    }
}
else {
    Write-Error "Resource group '$RGName' does not exist on this account"
}