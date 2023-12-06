using namespace System.Net

param($Timer)

Write-Host 'Starting process for standards.'
$Table = Get-CippTable -tablename 'standards'
$SkipList = Get-Tenants -SkipList
$Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

#Migrate from old standards to new standards.
$Tenants | Where-Object -Property 'v2' -NE $true | ForEach-Object {
    $OldStd = $_
    $OldStd.standards.psobject.properties.name | ForEach-Object {
        $OldStd.Standards.$_ = [pscustomobject]@{ remediate = $true }
    }
    $OldStd | Add-Member -NotePropertyName 'v2' -NotePropertyValue $true -PassThru -Force
    $Entity = @{ 
        PartitionKey = 'standards'
        RowKey       = "$($OldStd.Tenant)"
        JSON         = "$($OldStd | ConvertTo-Json -Depth 10)"
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
}

#Execute standards

$object = foreach ($Tenant in $Tenants) {
    $Tenant.standards.psobject.properties.name | ForEach-Object {
        $Standard = $_
        if ($Tenant.Tenant -ne 'AllTenants' -and $SkipList.defaultDomainName -notcontains $Tenant.Tenant) {
            if ($Standard -ne 'OverrideAllTenants') {
                [pscustomobject]@{
                    Tenant   = $tenant.Tenant
                    Standard = $Standard
                    Settings = $Tenant.standards.$Standard
                }
            }
        } elseif ($Tenant.Tenant -eq 'AllTenants') {
            Write-Host "Working on all Tenants Standard. Showing which tasks we'll run below this."
            Get-Tenants | ForEach-Object {
                $TenantForStandard = $_
                $TenantStandard = $Tenants | Where-Object { $_.Tenant -eq $TenantForStandard.defaultDomainName }
                if ($TenantStandard.standards.OverrideAllTenants.remediate -ne $true) {
                    Write-Host "$($TenantForStandard.defaultDomainName) - $Standard"
                    [pscustomobject]@{
                        Tenant   = $_.defaultDomainName
                        Standard = $Standard
                        Settings = $Tenant.standards.$Standard
                    }
                }
            }
        }
    }
}

#For each item in our object, run the queue. 
$object | Where-Object -Property Standard -NE 'v2' #filter out the v2 standard

foreach ($task in $object) {
    $QueueItem = [pscustomobject]@{
        Tenant   = $task.Tenant
        Standard = $task.Standard
        Settings = $task.Settings
    }
    
}