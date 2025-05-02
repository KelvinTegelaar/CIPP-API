function Invoke-CIPPStandardPhishSimSpoofIntelligence {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PhishSimSpoofIntelligence
    .SYNOPSIS
        (Label) Add allowed domains to Spoof Intelligence
    .DESCRIPTION
        (Helptext) This adds allowed domains to the Spoof Intelligence Allow/Block List.
        (DocsDescription) This adds allowed domains to the Spoof Intelligence Allow/Block List.
    .NOTES
        CAT
            Defender Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"label":"Allowed Domains","name":"standards.PhishSimSpoofIntelligence.AllowedDomains"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-03-28
        POWERSHELLEQUIVALENT
            New-TenantAllowBlockListSpoofItems
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#medium-impact
    #>

    param($Tenant, $Settings)
    # Fetch current Phishing Simulations Spoof Intelligence domains and ensure it is correctly configured
    $DomainState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-TenantAllowBlockListSpoofItems' |
    Select-Object -Property Identity,SendingInfrastructure

    [String[]]$AddDomain = $Settings.AllowedDomains.value | Where-Object { $_ -notin $DomainState.SendingInfrastructure }

    $RemoveDomain = $DomainState | Where-Object { $_.SendingInfrastructure -notin $Settings.AllowedDomains.value } |
    Select-Object -Property Identity,SendingInfrastructure

    $StateIsCorrect = ($AddDomain.Count -eq 0 -and $RemoveDomain.Count -eq 0)

    $CompareField = [PSCustomObject]@{
        "Missing Domains"   = $AddDomain -join ', '
        "Incorrect Domains" = $RemoveDomain.SendingInfrastructure -join ', '
    }

    If ($Settings.remediate -eq $true) {
        If ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spoof Intelligence Allow list already correctly configured' -sev Info
        } Else {
            $BulkRequests = New-Object System.Collections.Generic.List[Hashtable]

            # Prepare removal requests
            If ($RemoveDomain.Count -gt 0) {
                Write-Host "Removing $($RemoveDomain.Count) domains from Spoof Intelligence"
                $BulkRequests.Add(@{
                    CmdletInput = @{
                        CmdletName = 'Remove-TenantAllowBlockListSpoofItems'
                        Parameters = @{ Identity = 'default'; Ids = $RemoveDomain.Identity }
                    }
                })
            }

            # Prepare addition requests
            ForEach ($Domain in $AddDomain) {
                $BulkRequests.Add(@{
                    CmdletInput = @{
                        CmdletName = 'New-TenantAllowBlockListSpoofItems'
                        Parameters = @{ Identity = 'default'; Action = 'Allow'; SendingInfrastructure = $Domain; SpoofedUser = '*'; SpoofType = 'Internal' }
                    }
                })
                $BulkRequests.Add(@{
                    CmdletInput = @{
                        CmdletName = 'New-TenantAllowBlockListSpoofItems'
                        Parameters = @{ Identity = 'default'; Action = 'Allow'; SendingInfrastructure = $Domain; SpoofedUser = '*'; SpoofType = 'External' }
                    }
                })
            }
            $RawExoRequest = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($BulkRequests)

            $LastError = $RawExoRequest | Select-Object -Last 1
            If ($LastError.error) {
                Foreach ($ExoError in $LastError.error) {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to process Spoof Intelligence Domain with error: $ExoError" -Sev Error
                }
            } Else {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Processed all Spoof Intelligence Domains successfully." -Sev Info
            }
        }
    }

    If ($Settings.alert -eq $true) {
        If ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spoof Intelligence Allow list is correctly configured' -sev Info
        } Else {
            Write-StandardsAlert -message 'Spoof Intelligence Allow list is not correctly configured' -object $CompareField -tenant $Tenant -standardName 'PhishSimSpoofIntelligence' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -message 'Spoof Intelligence Allow list is not correctly configured' -sev Info
        }
    }

    If ($Settings.report -eq $true) {
        $FieldValue = $StateIsCorrect ? $true : $CompareField
        Set-CIPPStandardsCompareField -FieldName 'standards.PhishSimSpoofIntelligence' -FieldValue $FieldValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'PhishSimSpoofIntelligence' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
