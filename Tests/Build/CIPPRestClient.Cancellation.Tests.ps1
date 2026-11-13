BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPRestMethod.ps1')

    # Holds every connection open: /hang never answers, /slowbody sends headers and part of the body.
    $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $script:Listener.Start()
    $script:Base = "http://127.0.0.1:$($script:Listener.LocalEndpoint.Port)"
    $script:Server = [powershell]::Create().AddScript({
            param($Listener)
            $Held = [System.Collections.Generic.List[object]]::new()
            while ($true) {
                try { $Client = $Listener.AcceptTcpClient() } catch { break }
                $Held.Add($Client)
                $Stream = $Client.GetStream()
                $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                $Path = ($Reader.ReadLine() -split ' ')[1]
                while ($Reader.ReadLine()) { }
                if ($Path -eq '/slowbody') {
                    $Bytes = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: 1000`r`n`r`n{`"a`":")
                    $Stream.Write($Bytes, 0, $Bytes.Length)
                    $Stream.Flush()
                }
            }
        }).AddArgument($script:Listener)
    $null = $script:Server.BeginInvoke()

    function Invoke-Timed([scriptblock]$Call, [switch]$Outer) {
        $Watch = [System.Diagnostics.Stopwatch]::StartNew()
        try { & $Call; $Err = $null } catch { $Err = if ($Outer) { $_.Exception } else { $_.Exception.InnerException ?? $_.Exception } }
        [pscustomobject]@{ Error = $Err; Ms = $Watch.ElapsedMilliseconds }
    }
    function Get-DefaultTransportErrors { [int](([CIPP.CIPPRestClient]::GetDiagnostics() | ConvertFrom-Json).PoolUsage.TransportErrors.Default) }
}

AfterAll {
    $script:Listener.Stop()
    $script:Server.Dispose()
    Remove-Variable -Name CraftPipelineStopToken -Scope Global -ErrorAction SilentlyContinue
}

Describe 'CIPPRestClient cancellation' {
    It 'Send stops on the caller token as a cancellation, not a transport error' {
        $Before = Get-DefaultTransportErrors
        $Cts = [System.Threading.CancellationTokenSource]::new(300)
        $Result = Invoke-Timed { [CIPP.CIPPRestClient]::Send("$script:Base/hang", 'GET', $null, $null, $null, $true, 15, -1, $Cts.Token) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
        $Result.Ms | Should -BeLessThan 5000
        Get-DefaultTransportErrors | Should -Be $Before
    }

    It 'Send stops on the caller token while reading the body' {
        $Cts = [System.Threading.CancellationTokenSource]::new(300)
        $Result = Invoke-Timed { [CIPP.CIPPRestClient]::Send("$script:Base/slowbody", 'GET', $null, $null, $null, $true, 15, -1, $Cts.Token) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
        $Result.Ms | Should -BeLessThan 5000
    }

    It 'Send without a token still times out on timeoutSec' {
        $Result = Invoke-Timed { [CIPP.CIPPRestClient]::Send("$script:Base/hang", 'GET', $null, $null, $null, $true, 1, -1) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
        $Result.Ms | Should -BeGreaterOrEqual 900
    }

    It 'SendConcurrent stops on the caller token instead of retrying' {
        $Requests = [CIPP.CIPPConcurrentRequest[]]@(1..3 | ForEach-Object { [CIPP.CIPPConcurrentRequest]@{ Uri = "$script:Base/hang"; TimeoutSec = 15 } })
        $Cts = [System.Threading.CancellationTokenSource]::new(300)
        $Result = Invoke-Timed { [CIPP.CIPPRestClient]::SendConcurrent($Requests, 3, 3, $Cts.Token) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
        $Result.Ms | Should -BeLessThan 5000
    }

    It 'Invoke-CIPPRestMethod returns when Craft stops its pipeline' {
        # As Craft does: cancel the global token (PS 7.4), then stop the pipeline (PipelineStopToken on 7.6+).
        $Cts = [System.Threading.CancellationTokenSource]::new()
        $Shell = [powershell]::Create().AddScript({
                param($Function, $Uri, $Token)
                $global:CraftPipelineStopToken = $Token
                . $Function
                Invoke-CIPPRestMethod -Uri $Uri -TimeoutSec 15
            }).AddArgument((Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPRestMethod.ps1')).AddArgument("$script:Base/hang").AddArgument($Cts.Token)
        $Watch = [System.Diagnostics.Stopwatch]::StartNew()
        $Async = $Shell.BeginInvoke()
        Start-Sleep -Milliseconds 500
        $Cts.Cancel()
        $Shell.Stop()
        $Watch.ElapsedMilliseconds | Should -BeLessThan 5000
        $Async.IsCompleted | Should -BeTrue
        $Shell.Dispose()
    }

    It 'Invoke-CIPPRestMethod without a stop token still reports a timeout' {
        $Result = Invoke-Timed -Outer { Invoke-CIPPRestMethod -Uri "$script:Base/hang" -TimeoutSec 1 }
        $Result.Error | Should -BeOfType [System.TimeoutException]
    }
}
