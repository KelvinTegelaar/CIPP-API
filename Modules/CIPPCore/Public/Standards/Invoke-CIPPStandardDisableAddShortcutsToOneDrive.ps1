function Invoke-CIPPStandardDisableAddShortcutsToOneDrive {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        function GetTenantRequestXml {
            return @'
        <Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0"
            ApplicationName="SharePoint Online PowerShell (16.0.23814.0)"
            xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009">
            <Actions>
                <ObjectPath Id="4" ObjectPathId="3" />
                <Query Id="5" ObjectPathId="3">
                    <Query SelectAllProperties="true">
                        <Properties />
                    </Query>
                </Query>
            </Actions>
            <ObjectPaths>
                <Constructor Id="3" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" />
            </ObjectPaths>
        </Request>
'@
        }

        function GetDisableAddShortcutsToOneDriveXml {
            param(
                [string]$identity
            )

            # the json object gives us a space and a newline :(
            $identity = $identity.Replace(' ', '')
            $identity = $identity.Replace("`n", '&#xA;')
            return @"
        <Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0"
            LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.23814.0)"
            xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009">
            <Actions>
                <SetProperty Id="7" ObjectPathId="3" Name="DisableAddToOneDrive">
                    <Parameter Type="Boolean">true</Parameter>
                </SetProperty>
            </Actions>
            <ObjectPaths>
                <Identity Id="3" Name="$identity" />
            </ObjectPaths>
        </Request>
"@
        }

        $log = @{
            API     = 'Standards'
            tenant  = $tenant
            message = ''
            sev     = 'Info'
        }

        try {
            $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -tenantid $TenantFilter).id.Split('.')[0]
            $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"
            $graphRequest = @{
                'scope'       = "$AdminURL/.default"
                'tenantid'    = $tenant
                'uri'         = "$AdminURL/_vti_bin/client.svc/ProcessQuery"
                'type'        = 'POST'
                'body'        = GetTenantRequestXml
                'ContentType' = 'text/xml'
            }

            $response = New-GraphPostRequest @graphRequest
            if (!$response.ErrorInfo.ErrorMessage) {
                $log.message = 'Received Tenant from Sharepoint'
                Write-LogMessage @log
            }

            $graphRequest.Body = GetDisableAddShortcutsToOneDriveXml -identity $response._ObjectIdentity_
            $response = New-GraphPostRequest @graphRequest

            if (!$response.ErrorInfo.ErrorMessage) {
                $log.message = "Set DisableAddShortcutsToOneDrive to True on $tenant"
            } else {
                $log.message = "Unable to set DisableAddShortcutsToOneDrive to True `
            on $($Tenant, $Settings): $($response.ErrorInfo.ErrorMessage)"
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $log.message = "Failed to set OneDrive shortcut: $ErrorMessage"
            $log.sev = 'Error'
        }

        Write-LogMessage @log
    }
}
