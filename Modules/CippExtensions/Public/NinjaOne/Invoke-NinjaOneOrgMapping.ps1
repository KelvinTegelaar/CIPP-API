function Invoke-NinjaOneOrgMapping {

    [System.Collections.Generic.List[PSCustomObject]]$MatchedM365Tenants = @()
    [System.Collections.Generic.List[PSCustomObject]]$MatchedNinjaOrgs = @()

    $ExcludeSerials = @('0', 'SystemSerialNumber', 'To Be Filled By O.E.M.', 'System Serial Number', '0123456789', '123456789', '............')
    $CIPPMapping = Get-CIPPTable -TableName CippMapping


    #Get available mappings
    $Mappings = [pscustomobject]@{}
    $Filter = "PartitionKey eq 'NinjaOneMapping'"
    Get-AzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.IntegrationName)"; value = "$($_.IntegrationId)" }
    }

    #Get Available Tenants
    $Tenants = Get-Tenants -IncludeErrors
    #Get available Ninja clients
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne

    $Token = Get-NinjaOneToken -configuration $Configuration

    # Fetch Ninja Orgs
    $After = 0
    $PageSize = 1000
    $NinjaOrgs = do {
        $Result = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organizations?pageSize=$PageSize&after=$After" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
        $Result
        $ResultCount = ($Result.id | Measure-Object -Maximum)
        $After = $ResultCount.maximum

    } while ($ResultCount.count -eq $PageSize)

    # Exclude tenants already mapped.
    Foreach ($ExistingMap in $mappings.psobject.properties) {
        $ExistingTenant = $Tenants | Where-Object { $_.customerId -eq $ExistingMap.name }
        $ExistingOrg = $NinjaOrgs | Where-Object { $_.id -eq $ExistingMap.value.value }

        if (($ExistingTenant | Measure-Object).count -eq 1) {
            $MatchedM365Tenants.add($ExistingTenant)
        }

        if (($ExistingOrg | Measure-Object).count -eq 1) {
            $MatchedM365Tenants.add($ExistingOrg)
        }
    }

    # Fetch Ninja Devices
    $After = 0
    $PageSize = 1000
    $NinjaDevicesRaw = do {
        $Result = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/devices-detailed?pageSize=$PageSize&after=$After" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
        $Result
        $ResultCount = ($Result.id | Measure-Object -Maximum)
        $After = $ResultCount.maximum

    } while ($ResultCount.count -eq $PageSize)


    $NinjaDevices = $NinjaDevicesRaw | Where-Object { $null -ne $_.system.serialNumber -and $_.system.serialNumber -notin $ExcludeSerials } | ForEach-Object {
        [pscustomobject]@{
            ID               = $_.id
            SystemName       = $_.systemName
            DNSName          = $_.dnsName
            Serial           = $_.system.serialNumber
            BiosSerialNumber = $_.system.biosSerialNumber
            OrgID            = $_.organizationId
        }
    }

    # Remove any devices with duplicate serials
    $ParsedNinjaDevices = $NinjaDevices | Where-Object { $_.Serial -in (($NinjaDevices | Group-Object Serial | Where-Object { $_.count -eq 1 }).name) }


    # First lets match on Org names
    foreach ($Tenant in $Tenants | Where-Object { $_.customerId -notin $MatchedM365Tenants.customerId }) {
        $MatchedOrg = $NinjaOrgs | Where-Object { $_.name -eq $Tenant.displayName }
        if (($MatchedOrg | Measure-Object).count -eq 1) {
            $MatchedM365Tenants.add($Tenant)
            $MatchedNinjaOrgs.add($MatchedOrg)
            $AddObject = @{
                PartitionKey    = 'NinjaOneMapping'
                RowKey          = "$($Tenant.customerId)"
                IntegrationId   = "$($MatchedOrg.id)"
                IntegrationName = "$($MatchedOrg.name)"
            }
            Add-AzDataTableEntity @CIPPMapping -Entity $AddObject -Force
            Write-LogMessage -API 'NinjaOneAutoMap_Queue' -Headers'CIPP' -message "Added mapping from Organization name match for $($Tenant.customerId). to $($($MatchedOrg.name))" -Sev 'Info'
        }
    }

    # Now Let match on remaining Tenants

    $Batch = Foreach ($Tenant in $Tenants | Where-Object { $_.customerId -notin $MatchedM365Tenants.customerId }) {
        [PSCustomObject]@{
            'NinjaAction'  = 'AutoMapTenant'
            'M365Tenant'   = $Tenant
            'NinjaOrgs'    = $NinjaOrgs | Where-Object { $_.id -notin $MatchedNinjaOrgs }
            'NinjaDevices' = $ParsedNinjaDevices
            'FunctionName' = 'NinjaOneQueue'
        }
    }
    if (($Batch | Measure-Object).Count -gt 0) {
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'NinjaOneOrchestrator'
            Batch            = @($Batch)
        }
        #Write-Host ($InputObject | ConvertTo-Json)
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Host "Started permissions orchestration with ID = '$InstanceId'"
    }
}
