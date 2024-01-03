 
function Invoke-CIPPStandardsRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants'
    )
    Write-Host "Starting process for standards - $($tenantFilter)"
    $Table = Get-CippTable -tablename 'standards'
    $SkipList = Get-Tenants -SkipList
    if ($tenantfilter -ne 'allTenants') {
        $Filter = "PartitionKey eq 'standards' and RowKey eq '$($tenantfilter)'"
    } else {
        $Filter = "PartitionKey eq 'standards'"
    }
    $Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    #Migrate from old standards to new standards.
    $Tenants | Where-Object -Property 'v2.1' -NE $null | ForEach-Object {
        $OldStd = $_
        $OldStd.standards.psobject.properties.name | ForEach-Object {
            if ($_ -eq 'MailContacts') {
                $OldStd.Standards.$_ = [pscustomobject]@{ 
                    GeneralContact   = $OldStd.Standards.MailContacts.GeneralContact.Mail
                    SecurityContact  = $OldStd.Standards.MailContacts.SecurityContact.Mail
                    MarketingContact = $OldStd.Standards.MailContacts.MarketingContact.Mail
                    TechContact      = $OldStd.Standards.MailContacts.TechContact.Mail
                    remediate        = $true
                }
            } else {
                if ($OldStd.Standards.$_ -eq $true -and $_ -ne 'v2.1') { 
                    $OldStd.Standards.$_ = @{ remediate = $true } 
                } else { 
                    $OldStd.Standards.$_ | Add-Member -NotePropertyName 'remediate' -NotePropertyValue $true -Force 
                }
                
            }
        }
        $OldStd | Add-Member -NotePropertyName 'v2.1' -NotePropertyValue $true -PassThru -Force
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

    foreach ($task in $object | Where-Object -Property Standard -NotLike 'v2*') {
        $QueueItem = [pscustomobject]@{
            Tenant       = $task.Tenant
            Standard     = $task.Standard
            Settings     = $task.Settings
            FunctionName = 'CIPPStandard'
        }
        Push-OutputBinding -Name QueueItem -Value $QueueItem
    }
}