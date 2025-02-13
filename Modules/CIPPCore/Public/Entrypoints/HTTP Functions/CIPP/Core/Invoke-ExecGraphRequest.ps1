using namespace System.Net

Function Invoke-ExecGraphRequest {
        <#
    .FUNCTIONALITY
    Entrypoint
    #>
        [CmdletBinding()]
        param($Request, $TriggerMetadata)

        $APIName = $Request.Params.CIPPEndpoint
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        Function ConvertTo-FlatObject {
                # https://evotec.xyz/powershell-converting-advanced-object-to-flat-object/ - MIT License
                [CmdletBinding()]
                Param (
                        [Parameter(ValueFromPipeLine)][Object[]]$Objects,
                        [String]$Separator = '.',
                        [ValidateSet('', 0, 1)]$Base = 1,
                        [int]$Depth = 5,
                        [Parameter(DontShow)][String[]]$Path,
                        [Parameter(DontShow)][System.Collections.IDictionary] $OutputObject
                )
                Begin {
                        $InputObjects = [System.Collections.Generic.List[Object]]::new()
                }
                Process {
                        foreach ($O in $Objects) {
                                $InputObjects.Add($O)
                        }
                }
                End {
                        If ($PSBoundParameters.ContainsKey('OutputObject')) {
                                $Object = $InputObjects[0]
                                $Iterate = [ordered] @{}
                                if ($null -eq $Object) {
                                        #Write-Verbose -Message "ConvertTo-FlatObject - Object is null"
                                } elseif ($Object.GetType().Name -in 'String', 'DateTime', 'TimeSpan', 'Version', 'Enum') {
                                        $Object = $Object.ToString()
                                } elseif ($Depth) {
                                        $Depth--
                                        If ($Object -is [System.Collections.IDictionary]) {
                                                $Iterate = $Object
                                        } elseif ($Object -is [Array] -or $Object -is [System.Collections.IEnumerable]) {
                                                $i = $Base
                                                foreach ($Item in $Object.GetEnumerator()) {
                                                        $Iterate["$i"] = $Item
                                                        $i += 1
                                                }
                                        } else {
                                                foreach ($Prop in $Object.PSObject.Properties) {
                                                        if ($Prop.IsGettable) {
                                                                $Iterate["$($Prop.Name)"] = $Object.$($Prop.Name)
                                                        }
                                                }
                                        }
                                }
                                If ($Iterate.Keys.Count) {
                                        foreach ($Key in $Iterate.Keys) {
                                                ConvertTo-FlatObject -Objects @(, $Iterate["$Key"]) -Separator $Separator -Base $Base -Depth $Depth -Path ($Path + $Key) -OutputObject $OutputObject
                                        }
                                } else {
                                        $Property = $Path -Join $Separator
                                        $OutputObject[$Property] = $Object
                                }
                        } elseif ($InputObjects.Count -gt 0) {
                                foreach ($ItemObject in $InputObjects) {
                                        $OutputObject = [ordered]@{}
                                        ConvertTo-FlatObject -Objects @(, $ItemObject) -Separator $Separator -Base $Base -Depth $Depth -Path $Path -OutputObject $OutputObject
                                        [PSCustomObject] $OutputObject
                                }
                        }
                }
        }
        $TenantFilter = $Request.Query.TenantFilter
        try {
                if ($TenantFilter -ne 'AllTenants') {
                        $RawGraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$($Request.Query.Endpoint)" -tenantid $TenantFilter -NoPagination [boolean]$Request.query.DisablePagination -ComplexFilter
                } else {
                        $RawGraphRequest = Get-Tenants | ForEach-Object -Parallel {
                                Import-Module '.\Modules\AzBobbyTables'
                                Import-Module '.\Modules\CIPPCore'
                                try {
                                        $DefaultDomainName = $_.defaultDomainName
                                        $TenantName = $_.displayName
                                        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$($using:Request.Query.Endpoint)" -tenantid $DefaultDomainName -NoPagination [boolean]$using:Request.query.DisablePagination -ComplexFilter | Select-Object @{
                                                label      = 'Tenant'
                                                expression = { $TenantName }
                                        }, *
                                } catch {
                                        continue
                                }
                        }

                }
                $GraphRequest = $RawGraphRequest | Where-Object -Property '@odata.context' -EQ $null | ConvertTo-FlatObject
                $StatusCode = [HttpStatusCode]::OK
        } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $StatusCode = [HttpStatusCode]::Forbidden
                $GraphRequest = $ErrorMessage
        }

        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = $StatusCode
                        Body       = @($GraphRequest)
                })

}
