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
        $Results = foreach ($Function in $Functions) {
            if ($Function -in $TemporaryBlacklist) { continue }
            $GetHelp = @{
                Name = $Function
            }
            if ($Module -eq 'ExchangeOnlineManagement') {
                $GetHelp.Path = 'ExchangeOnlineHelp'
            }
            $Help = Get-Help @GetHelp
            $ParamsHelp = ($Help | Select-Object -ExpandProperty parameters).parameter | Select-Object name, @{n = 'description'; exp = { $_.description.Text } }
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
                        Required    = $Param.Attributes.Mandatory
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
