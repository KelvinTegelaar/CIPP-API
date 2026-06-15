function Invoke-ListFunctionParameters {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $Module = $Request.Query.Module
    $Function = $Request.Query.Function

    $CommandQuery = @{}
    if ($Module) {
        $CommandQuery.Module = $Module
    }
    if ($Function) {
        $CommandQuery.Name = $Function
    }
    $IgnoreList = 'entryPoint', 'internal'
    $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'TenantFilter', 'APIName', 'Headers', 'ProgressAction', 'WhatIf', 'Confirm', 'Headers', 'NoAuthCheck')
    $TemporaryBlacklist = 'Get-CIPPAuthentication', 'Invoke-CippWebhookProcessing', 'Invoke-ListFunctionParameters', 'New-CIPPAPIConfig', 'New-CIPPGraphSubscription'

    if (-not $global:CIPPFunctionParameters) {
        $ParametersFileJson = Join-Path $env:CIPPRootPath 'Config\function-parameters.json'

        if (Test-Path $ParametersFileJson) {
            try {
                $jsonData = [System.IO.File]::ReadAllText($ParametersFileJson) | ConvertFrom-Json -AsHashtable
            } catch {
                Write-Warning "Failed to load function parameters from JSON: $($_.Exception.Message)"
            }

            if ($jsonData) {
                $global:CIPPFunctionParameters = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($key in $jsonData.Keys) {
                    $global:CIPPFunctionParameters[$key] = $jsonData[$key]
                }
            }
        }
    }

    try {
        if ($Module -eq 'ExchangeOnlineManagement') {
            $ExoRequest = @{
                AvailableCmdlets = $true
                tenantid         = $env:TenantID
                NoAuthCheck      = $true
            }
            if ($Request.Query.Compliance -eq $true) {
                $ExoRequest.Compliance = $true
            }
            $Functions = New-ExoRequest @ExoRequest
            #Write-Host $Functions
        } else {
            $Functions = Get-Command @CommandQuery | Where-Object { $_.Visibility -eq 'Public' }
        }
        $HasParameterCache = $global:CIPPFunctionParameters -and $global:CIPPFunctionParameters.Count -gt 0
        $Results = foreach ($Function in $Functions) {
            if ($Function -in $TemporaryBlacklist) { continue }

            $Help = $null
            $ParamsHelp = $null

            if ($Module -ne 'ExchangeOnlineManagement' -and $HasParameterCache -and $Function.Name -and $global:CIPPFunctionParameters.ContainsKey($Function.Name)) {
                $CachedFunction = $global:CIPPFunctionParameters[$Function.Name]
                $Help = [PSCustomObject]@{
                    Functionality = $CachedFunction['Functionality']
                    Synopsis      = $CachedFunction['Synopsis']
                }
                $ParamsHelp = @($CachedFunction['Parameters']) | Select-Object Name, @{n = 'description'; exp = { $_['Description'] } }
            } elseif ($Module -ne 'ExchangeOnlineManagement' -and $HasParameterCache) {
                continue
            } else {
                $GetHelp = @{
                    Name = $Function
                }
                if ($Module -eq 'ExchangeOnlineManagement') {
                    $GetHelp.Path = 'ExchangeOnlineHelp'
                }
                $Help = Get-Help @GetHelp
                $ParamsHelp = ($Help | Select-Object -ExpandProperty parameters).parameter | Select-Object name, @{n = 'description'; exp = { $_.description.Text } }
            }

            if ($Help.Functionality -in $IgnoreList) { continue }
            if ($Help.Functionality -match 'Entrypoint') { continue }
            $Parameters = foreach ($Key in $Function.Parameters.Keys) {
                if ($CommonParameters -notcontains $Key) {
                    $Param = $Function.Parameters.$Key
                    $ParamHelp = $ParamsHelp | Where-Object { $_.name -eq $Key }
                    [PSCustomObject]@{
                        Name        = $Key
                        Type        = $Param.ParameterType.FullName
                        Description = $ParamHelp.description
                        Required    = [bool]$Param.Attributes.Mandatory
                    }
                }
            }
            [PSCustomObject]@{
                Function   = $Function.Name
                Synopsis   = $Help.Synopsis
                Parameters = @($Parameters)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results
    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Results)
    }

}
