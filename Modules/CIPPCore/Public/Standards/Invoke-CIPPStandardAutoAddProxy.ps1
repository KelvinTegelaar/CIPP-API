function Invoke-CIPPStandardAutoAddProxy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutoAddProxy
    .SYNOPSIS
        (Label) Automatically deploy proxy addresses
    .DESCRIPTION
        (Helptext) Automatically adds all available domains as a proxy address.
        (DocsDescription) Automatically finds all available domain names in the tenant, and tries to add proxy addresses based on the user's UPN to each of these.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-02-07
        POWERSHELLEQUIVALENT
            Set-Mailbox -EmailAddresses @{add=\$EmailAddress}
        RECOMMENDEDBY
        DISABLEDFEATURES
            
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#medium-impact
    #>
    param(
        $Tenant,
        $Settings,
        $QueueItem
    )

    $Domains = New-ExoRequest -TenantId $Tenant -Cmdlet 'Get-AcceptedDomain' | Select-Object -ExpandProperty DomainName
    $AllMailboxes = New-ExoRequest -TenantId $Tenant -Cmdlet 'Get-Mailbox'
    
    $MissingProxies = 0
    foreach ($Domain in $Domains) {
        $ProcessMailboxes = $AllMailboxes | Where-Object {
            $addresses = @($_.EmailAddresses) -replace '^[^:]+:'    # remove SPO:, SMTP:, etc.
            $hasDomain = $addresses | Where-Object { $_ -like "*@$Domain" }
            if ($hasDomain) { return $false } else { return $true }
        }
        $MissingProxies += $ProcessMailboxes.Count
    }
    
    $StateIsCorrect = $MissingProxies -eq 0
    
    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect ? $true : $MissingProxies
        Set-CIPPStandardsCompareField -FieldName 'standards.AutoAddProxy' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AutoAddProxy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
    
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have proxy addresses for all domains' -sev Info
        } else {
            Write-StandardsAlert -message "There are $MissingProxies missing proxy addresses across all mailboxes" -object @{MissingProxies = $MissingProxies } -tenant $Tenant -standardName 'AutoAddProxy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "There are $MissingProxies missing proxy addresses across all mailboxes" -sev Info
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes already have proxy addresses for all domains' -sev Info
        } else {
            foreach ($Domain in $Domains) {
                $ProcessMailboxes = $AllMailboxes | Where-Object {
                    $addresses = @($_.EmailAddresses) -replace '^[^:]+:'    # remove SPO:, SMTP:, etc.
                    $hasDomain = $addresses | Where-Object { $_ -like "*@$Domain" }
                    if ($hasDomain) { return $false } else { return $true }
                }

                $bulkRequest = foreach ($Mailbox in $ProcessMailboxes) {
                    $LocalPart = $Mailbox.UserPrincipalName -split '@' | Select-Object -First 1
                    $NewAlias = "$LocalPart@$Domain"
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{Identity = $Mailbox.Identity ; EmailAddresses = @{
                                    '@odata.type' = '#Exchange.GenericHashTable'
                                    Add           = "smtp:$NewAlias"
                                }
                            }
                        }
                    }
                }
                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($bulkRequest)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-CippException -Exception $_.error
                        Write-Host "Failed to apply new email policy to $($_.target) Error: $($ErrorMessage.NormalizedError)"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply proxy address to $($_.error.target) Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    }
                }
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Added missing proxy addresses to mailboxes' -sev Info
        }
    }
}
