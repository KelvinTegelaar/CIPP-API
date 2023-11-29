if (!(Get-Module -ListAvailable Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Confirm:$false -Force -AllowPrerelease
}

$ResourceGroup = '##RESOURCEGROUP##'
$Subscription = '##SUBSCRIPTION##'
$FunctionName = '##FUNCTIONAPP##'
$TokenIP = '##TOKENIP##'

$Logo = @'
   _____ _____ _____  _____  
  / ____|_   _|  __ \|  __ \ 
 | |      | | | |__) | |__) |
 | |      | | |  ___/|  ___/ 
 | |____ _| |_| |    | |     
  \_____|_____|_|    |_|     
                
'@
Write-Host $Logo

Write-Host '=== Conditional Access Management ==='
if (Test-Path -Path '.\cipp-function-namedLocation.json') {
    $UseCache = Read-Host -Prompt 'Used cached Named Location for CIPP? (Y/n)'
    if ($UseCache -ne 'n') {
        $ipNamedLocation = Get-Content -Path '.\cipp-function-namedLocation.json' | ConvertFrom-Json -AsHashtable
    }
}

if (!($ipNamedLocation)) {
    Write-Host "`n- Connecting to Azure"
    Connect-AzAccount -Identity -Subscription $Subscription | Out-Null
    $Function = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $FunctionName

    Write-Host 'Getting Function App IP addresses'
    # Get possible IPs from function app
    $PossibleIpAddresses = (($Function | Select-Object -ExpandProperty PossibleOutboundIpAddress) + ',' + $TokenIP) -split ','

    # Convert possible IP addresses to ipv4CidrRange list
    $ipRanges = foreach ($Ip in $PossibleIpAddresses) {
        $Cidr = '{0}/32' -f $Ip
        @{
            '@odata.type' = '#microsoft.graph.iPv4CidrRange'
            'cidrAddress' = $Cidr 
        }
    }

    # Return ipNamedLocation object
    $ipNamedLocation = @{
        '@odata.type' = '#microsoft.graph.ipNamedLocation'
        displayName   = ('CyberDrain Improved Partner Portal - {0}' -f $FunctionName)
        isTrusted     = $true
        ipRanges      = $ipRanges
    }

    $ipNamedLocation | ConvertTo-Json -Depth 10 | Out-File -Path '.\cipp-function-namedLocation.json'
    Write-Host 'Named location policy created and saved to .\cipp-function-namedLocation.json'
}

Write-Host "`n- Connecting to Customer Graph API, ensure you log in from a system that is allowed through the Conditional Access policy"
Select-MgProfile -Name 'beta'
$GraphOptions = @{ 
    Scopes                  = @('Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Application.Read.All')
    UseDeviceAuthentication = $true
}

do {
    Connect-MgGraph @GraphOptions
    $Context = Get-MgContext
    if ($Context) {
        Write-Host "Connected as $($Context.Account) ($($Context.TenantId))"
        $Switch = Read-Host -Prompt 'Switch Accounts? (y/N)'
        if ($Switch -eq 'y') {
            Disconnect-MgGraph | Out-Null
        }
    }
}
while (!(Get-MgContext))

Write-Host "`n- Getting existing policies"
$Policies = Get-MgIdentityConditionalAccessPolicy
Write-Host($Policies.displayName -join "`n")

Write-Host "`n- Named Location Check"
$NamedLocations = Get-MgIdentityConditionalAccessNamedLocation
if ($NamedLocations.displayName -notcontains $ipNamedLocation.displayName) {
    Write-Host "Creating Named Location: '$($ipNamedLocation.displayName)'"
    $NamedLocation = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $ipNamedLocation
}
else {
    $NamedLocation = $NamedLocations | Where-Object { $_.displayName -eq $ipNamedLocation.displayName }
    Write-Host "Named Location exists: '$($NamedLocation.displayName)'"
    Update-MgIdentityConditionalAccessNamedLocation -NamedLocationId $NamedLocation.Id -BodyParameter $ipNamedLocation
}

Write-Host "`n- Conditional access policy check"
$ConfigPolicy = Read-Host -Prompt 'Exclude CIPP from existing CA policies? (Y/n)'
if ($ConfigPolicy -ne 'n') {
    foreach ($Policy in $Policies) {
        Write-Host "- Policy: $($Policy.displayName)"
        $Conditions = $Policy.Conditions
        $ExcludeLocations = $Conditions.Locations.ExcludeLocations
        $IncludeLocations = $Conditions.Locations.IncludeLocations
        if ($ExcludeLocations -eq 'AllTrusted' -or $ExcludeLocations -contains $NamedLocation.Id) {
            Write-Host 'Named location already excluded'
        }
        elseif ($IncludeLocations -eq 'AllTrusted' -or $IncludeLocations -contains $NamedLocation.Id) {
            Write-Host 'Named location is already included'
        }
        else {
            Write-Host 'Adding exclusion for named location'
            $Locations = [system.collections.generic.list[string]]::new()
            foreach ($Location in $ExcludeLocations) {
                $Locations.Add($Location) | Out-Null
            }
            $Locations.Add($NamedLocation.Id) | Out-Null
            $Conditions.Locations.ExcludeLocations = [string[]]$Locations
            if (!($Conditions.Locations.IncludeLocations)) { $Conditions.Locations.IncludeLocations = 'All' } 
            Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $Policy.Id -Conditions $Conditions
        }
    }
    Write-Host "`nDone."
}
