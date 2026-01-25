function Invoke-ListFunctionParameters {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    param($Request, $TriggerMetadata)

    $Module = $Request.Query.Module
    $Function = $Request.Query.Function

    $IgnoreList = @('entryPoint', 'internal')
    $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'TenantFilter', 'APIName', 'Headers', 'ProgressAction', 'WhatIf', 'Confirm', 'NoAuthCheck')
    $TemporaryBlacklist = @('Get-CIPPAuthentication', 'Invoke-CippWebhookProcessing', 'Invoke-ListFunctionParameters', 'New-CIPPAPIConfig', 'New-CIPPGraphSubscription')

    try {
        # Load cache once per runspace
        if ($null -eq $script:_FunctionParametersCache) {
            $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
            $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
            $CachePath = Join-Path $CIPPRoot 'Config\function-parameters.json'

            if (Test-Path $CachePath) {
                try {
                    $cacheData = Get-Content $CachePath -Raw | ConvertFrom-Json
                    # Keep as PSCustomObject - don't convert to hashtable to preserve property order
                    $script:_FunctionParametersCache = $cacheData.Functions
                    Write-Debug "Loaded function parameter cache:"
                } catch {
                    Write-Warning "Failed to load cache: $_"
                    $script:_FunctionParametersCache = [PSCustomObject]@{}
                }
            } else {
                Write-Warning "Cache file not found at $CachePath"
                $script:_FunctionParametersCache = [PSCustomObject]@{}
            }
        }

        $cache = $script:_FunctionParametersCache

        # Determine which functions to process
        if ($Module -eq 'ExchangeOnlineManagement') {
            # Special case for EXO - not in cache
            $ExoRequest = @{
                AvailableCmdlets = $true
                tenantid         = $env:TenantID
                NoAuthCheck      = $true
            }
            if ($Request.Query.Compliance -eq $true) {
                $ExoRequest.Compliance = $true
            }
            $Functions = New-ExoRequest @ExoRequest
            $UseCache = $false

        } elseif ($Function) {
            # Specific function requested - try cache first
            if ($cache.PSObject.Properties.Name -contains $Function) {
                $Functions = @([PSCustomObject]@{ Name = $Function })
                $UseCache = $true
            } else {
                # Not in cache, fall back to Get-Command
                $Functions = @(Get-Command -Name $Function -ErrorAction SilentlyContinue | Where-Object { $_.Visibility -eq 'Public' })
                $UseCache = $false
            }

        } elseif ($Module) {
            # Module(s) specified - filter cache by module
            $requestedModules = $Module -split ',' | ForEach-Object { $_.Trim() }

            $Functions = $cache.PSObject.Properties | Where-Object {
                $_.Value.Module -in $requestedModules
            } | ForEach-Object {
                [PSCustomObject]@{ Name = $_.Name }
            }
            $UseCache = $true

        } else {
            # No filter - return ALL cached functions
            $Functions = $cache.PSObject.Properties | ForEach-Object {
                [PSCustomObject]@{ Name = $_.Name }
            }
            $UseCache = $true
        }

        Write-Debug "Processing $($Functions.Count) functions (UseCache: $UseCache)"

        $Results = foreach ($Func in $Functions) {
            $FunctionName = if ($Func.Name) { $Func.Name } else { $Func.ToString() }

            # Skip blacklisted functions
            if ($FunctionName -in $TemporaryBlacklist) {
                continue
            }

            # Try cache first
            if ($UseCache -and ($cache.PSObject.Properties.Name -contains $FunctionName)) {
                $cachedFunc = $cache.$FunctionName

                # Filter by Functionality
                if ($cachedFunc.Functionality) {
                    $functionality = $cachedFunc.Functionality

                    # Skip if functionality is in ignore list or contains 'Entrypoint'
                    if ($functionality -in $IgnoreList -or $functionality -match 'Entrypoint') {
                        continue
                    }
                }

                # Parameters are already an array - return as-is to preserve order
                $Parameters = if ($cachedFunc.Parameters) {
                    $cachedFunc.Parameters
                } else {
                    @()
                }

                [PSCustomObject]@{
                    Function   = $FunctionName
                    Synopsis   = $cachedFunc.Synopsis
                    Parameters = $Parameters
                }

            } else {
                # Cache miss or EXO - use Get-Help (original logic)
                if ($Func -isnot [System.Management.Automation.CommandInfo]) {
                    $Func = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
                    if (-not $Func) { continue }
                }

                $GetHelp = @{ Name = $FunctionName }
                if ($Module -eq 'ExchangeOnlineManagement') {
                    $GetHelp.Path = 'ExchangeOnlineHelp'
                }

                try {
                    $Help = Get-Help @GetHelp -ErrorAction Stop
                    $ParamsHelp = ($Help | Select-Object -ExpandProperty parameters).parameter |
                                  Select-Object name, @{n = 'description'; exp = { $_.description.Text }}

                    # Filter by Functionality
                    if ($Help.Functionality -in $IgnoreList -or $Help.Functionality -match 'Entrypoint') {
                        continue
                    }

                    $Parameters = foreach ($Key in $Func.Parameters.Keys) {
                        if ($CommonParameters -notcontains $Key) {
                            $Param = $Func.Parameters.$Key
                            $ParamHelp = $ParamsHelp | Where-Object { $_.name -eq $Key }
                            [PSCustomObject]@{
                                Name        = $Key
                                Type        = $Param.ParameterType.FullName
                                Description = $ParamHelp.description
                                Required    = $Param.Attributes.Mandatory
                            }
                        }
                    }

                    [PSCustomObject]@{
                        Function   = $FunctionName
                        Synopsis   = $Help.Synopsis
                        Parameters = @($Parameters)
                    }
                } catch {
                    Write-Warning "Failed to get help for $FunctionName : $_"
                    continue
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        # Sort results by Function name before returning
        $SortedResults = $Results | Sort-Object Function
        Write-Debug "Returning $($SortedResults.Count) functions (sorted)"
        $SortedResults

    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($SortedResults)
    }
}
