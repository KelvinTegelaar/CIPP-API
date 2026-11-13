BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    Import-Module (Join-Path $RepoRoot 'Modules/AzBobbyTables') -ErrorAction Stop
    Get-AzDataTableSupportedEntityType | Out-Null
    # Azure.Core lives in the module's private AssemblyLoadContext, so take the type from there.
    $Core = @(foreach ($Context in [System.Runtime.Loader.AssemblyLoadContext]::All) {
            foreach ($Assembly in $Context.Assemblies) {
                if ($Assembly.GetName().Name -eq 'AzBobbyTables.Core') { $Assembly }
            }
        })[0]
    $Context = [System.Runtime.Loader.AssemblyLoadContext]::GetLoadContext($Core)
    $script:RequestFailedType = $Context.LoadFromAssemblyName([System.Reflection.AssemblyName]::new('Azure.Core')).GetType('Azure.RequestFailedException')

    function Get-CaughtStatus([scriptblock]$Thrower) {
        try { & $Thrower } catch { Get-CippErrorStatusCode -ErrorRecord $_ }
    }
}

Describe 'Get-CippErrorStatusCode' {
    It 'maps a typed ArgumentException thrown by a helper to 400' {
        Get-CaughtStatus { throw [System.ArgumentException]::new('SiteUrl is required.') } | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'maps an ItemNotFoundException to 404' {
        Get-CaughtStatus { throw [System.Management.Automation.ItemNotFoundException]::new('Template not found') } | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'maps an UnauthorizedAccessException from Assert-CippTenantAccess to 403' {
        Get-CaughtStatus { throw [System.UnauthorizedAccessException]::new("Your roles don't include t2.example.com.") } | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
    }

    It 'maps a plain string throw, as Graph helpers raise, to 500' {
        Get-CaughtStatus { throw 'Graph returned 503' } | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
    }

    It 'maps an Azure Storage <Status> to 503 so the frontend retries it' -ForEach @(
        @{ Status = 503 }
        @{ Status = 500 }
        @{ Status = 0 }
    ) {
        $Exception = [Activator]::CreateInstance($script:RequestFailedType, [object[]]@([int]$Status, 'The server is busy.'))

        Get-CaughtStatus { throw $Exception } | Should -Be ([System.Net.HttpStatusCode]::ServiceUnavailable)
    }

    It 'leaves an Azure Storage 409 as 500' {
        $Exception = [Activator]::CreateInstance($script:RequestFailedType, [object[]]@(409, 'Conflict'))

        Get-CaughtStatus { throw $Exception } | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
    }

    It 'finds the typed exception when PowerShell wraps it' {
        # A script block run through a .NET method surfaces as MethodInvocationException -> RuntimeException -> ArgumentException
        Get-CaughtStatus { { throw [System.ArgumentException]::new('bad') }.Invoke() } | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}
