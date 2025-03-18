using namespace System.Net

Function Invoke-ListStandardsCompare {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BestPracticeAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Create mock data for testing with the correct API structure
    # Only tenant data with values, no compliance information or standard values
    $Results = @(
        @{
            tenantFilter     = 'TenantOne'
            standardsResults = @(
                @{
                    standardId   = 'standards.MailContacts'
                    standardName = 'Mail Contacts'
                    value        = @{
                        GeneralContact   = 'user@contoso.com'
                        SecurityContact  = 'security@contoso.com'
                        MarketingContact = 'marketing@contoso.com'
                        TechContact      = 'tech@contoso.com'
                    }
                },
                @{
                    standardId   = 'standards.AuditLog'
                    standardName = 'Audit Log'
                    value        = $true
                },
                @{
                    standardId   = 'standards.ProfilePhotos'
                    standardName = 'Profile Photos'
                    value        = @{
                        state = @{
                            label = 'Enabled'
                            value = 'enabled'
                        }
                    }
                }
            )
        },
        @{
            tenantFilter     = 'dev.johnwduprey.com'
            standardsResults = @(
                @{
                    standardId   = 'standards.MailContacts'
                    standardName = 'Mail Contacts'
                    value        = @{
                        GeneralContact  = 'admin@fabrikam.com'
                        SecurityContact = 'security@fabrikam.com'
                    }
                },
                @{
                    standardId   = 'standards.AuditLog'
                    standardName = 'Audit Log'
                    value        = $false
                }
            )
        }
    )
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = (ConvertTo-Json -Depth 15 -InputObject $Results)
        })

}
