# Pester tests for New-CIPPSharepointSite
#
# SPSiteManager/create can only make Communication and group-less Team sites. The TeamGroup
# template creates the Microsoft 365 group app-only through Graph (SharePoint's own
# GroupSiteManager/CreateGroupEx rejects the GDAP/SAM caller) and waits for the site URL.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-SharePointAdminLink { param($Public, $tenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $extraHeaders, $UseCertificate, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $scope, $body, $type, $contentType, $AddedHeaders, $AsApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPSharepointSite.ps1')

    $script:Common = @{
        SiteName        = 'Project Alpha!'
        SiteDescription = 'desc'
        SiteOwner       = 'owner@contoso.com'
        TenantFilter    = 'contoso.onmicrosoft.com'
    }
}

Describe 'New-CIPPSharepointSite' {
    BeforeEach {
        Mock Get-SharePointAdminLink { [PSCustomObject]@{ AdminUrl = 'https://contoso-admin.sharepoint.com'; SharePointUrl = 'https://contoso.sharepoint.com' } }
        Mock Write-LogMessage {}
        Mock Start-Sleep {}
        Mock New-GraphGetRequest { [PSCustomObject]@{ webUrl = 'https://contoso.sharepoint.com/sites/ProjectAlpha' } }
        Mock New-GraphPOSTRequest {
            if ($uri -eq 'https://graph.microsoft.com/v1.0/groups') {
                [PSCustomObject]@{ id = 'group-id' }
            } elseif ($uri -like '*SPSiteManager/create') {
                [PSCustomObject]@{ SiteStatus = 2 }
            }
        }
    }

    Context 'TeamGroup template' {
        It 'creates a private Unified group app-only with the chosen owner and returns the site URL' {
            New-CIPPSharepointSite @Common -TemplateName TeamGroup | Should -Match 'sites/ProjectAlpha'

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/v1.0/groups' -and $AsApp -eq $true -and
                ($body | ConvertFrom-Json).mailNickname -eq 'ProjectAlpha' -and
                ($body | ConvertFrom-Json).groupTypes -contains 'Unified' -and
                ($body | ConvertFrom-Json).visibility -eq 'Private' -and
                ($body | ConvertFrom-Json).'owners@odata.bind' -contains 'https://graph.microsoft.com/v1.0/users/owner@contoso.com'
            }
            Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*groups/group-id/sites/root*' }
            Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $uri -like '*SPSiteManager/create' }
        }

        It 'honours -IsPublic and applies the sensitivity label' {
            New-CIPPSharepointSite @Common -TemplateName TeamGroup -IsPublic -SensitivityLabel 'label-guid'

            Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/v1.0/groups' -and
                ($body | ConvertFrom-Json).visibility -eq 'Public' -and
                ($body | ConvertFrom-Json).assignedLabels[0].labelId -eq 'label-guid'
            }
        }

        It 'reports the group as provisioning when the site URL is not available yet' {
            Mock New-GraphGetRequest { throw 'not found' }

            New-CIPPSharepointSite @Common -TemplateName TeamGroup | Should -Match 'still being provisioned'
            Should -Invoke New-GraphGetRequest -Times 10 -Exactly
        }

        It 'throws when the group cannot be created' {
            Mock New-GraphPOSTRequest { throw 'mailNickname already exists' }

            { New-CIPPSharepointSite @Common -TemplateName TeamGroup } | Should -Throw '*mailNickname already exists*'
        }
    }

    Context 'existing templates' {
        It 'still creates a group-less Team site through SPSiteManager/create' {
            New-CIPPSharepointSite @Common -TemplateName Team

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://contoso-admin.sharepoint.com/_api/SPSiteManager/create' -and
                ($body | ConvertFrom-Json).request.WebTemplate -eq 'STS#3'
            }
            Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/groups' }
        }
    }
}
