BeforeDiscovery {
    $Utf8 = [System.Text.Encoding]::UTF8
    $Bom = [byte[]](0xEF, 0xBB, 0xBF)
    $Cases = @(
        @{ Name = 'json'; ContentType = 'application/json; charset=utf-8'; Body = $Utf8.GetBytes("{`"value`":[{`"id`":`"1`",`"when`":`"2025-05-05T05:05:05Z`",`"name`":`"Zo$([char]0xEB)`"}]}") }
        @{ Name = 'array'; ContentType = 'application/json'; Body = $Utf8.GetBytes('[{"id":"1"}]') }
        @{ Name = 'bom'; ContentType = 'application/json'; Body = [byte[]]($Bom + $Utf8.GetBytes('{"a":1}')) }
        @{ Name = 'utf16'; ContentType = 'application/json; charset=utf-16'; Body = [System.Text.Encoding]::Unicode.GetBytes("{`"a`":`"$([char]0xE9)`"}") }
        @{ Name = 'sniffed'; ContentType = 'text/plain'; Body = $Utf8.GetBytes("  `r`n [1,2]") }
        @{ Name = 'blank'; ContentType = 'text/plain'; Body = $Utf8.GetBytes("  `r`n`t ") }
        @{ Name = 'nbsp'; ContentType = 'text/plain'; Body = $Utf8.GetBytes(" $([char]0xA0) ") }
        @{ Name = 'text'; ContentType = $null; Body = $Utf8.GetBytes('plain text') }
        @{ Name = 'empty'; ContentType = 'application/json'; Body = [byte[]]@() }
    )
    $JsonCases = @($Cases | Where-Object { $_.Name -in 'json', 'array', 'bom', 'utf16', 'sniffed' })
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    # A one-response-per-connection HTTP server: the request path picks the canned response.
    $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $script:Listener.Start()
    $script:Port = $script:Listener.LocalEndpoint.Port
    $script:Responses = [System.Collections.Concurrent.ConcurrentDictionary[string, byte[]]]::new()
    $script:Server = [powershell]::Create().AddScript({
            param($Listener, $Responses)
            while ($true) {
                $Client = $Listener.AcceptTcpClient()
                $Stream = $Client.GetStream()
                $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                $Path = ($Reader.ReadLine() -split ' ')[1].TrimStart('/')
                while ($Reader.ReadLine()) { }
                $Bytes = $Responses[$Path]
                $Stream.Write($Bytes, 0, $Bytes.Length)
                $Stream.Flush()
                $Client.Close()
            }
        }).AddArgument($script:Listener).AddArgument($script:Responses)
    $null = $script:Server.BeginInvoke()

    function Set-Response([string]$Name, [string]$ContentType, [byte[]]$Body, [string]$Encoding) {
        $Head = "HTTP/1.1 200 OK`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n"
        if ($ContentType) { $Head += "Content-Type: $ContentType`r`n" }
        if ($Encoding) { $Head += "Content-Encoding: $Encoding`r`n" }
        $script:Responses[$Name] = [byte[]]([System.Text.Encoding]::ASCII.GetBytes("$Head`r`n") + $Body)
    }
    function Get-Expected([string]$ContentType, [byte[]]$Body) {
        $Content = [System.Net.Http.ByteArrayContent]::new($Body)
        if ($ContentType) { $Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($ContentType) }
        $Content.ReadAsStringAsync().GetAwaiter().GetResult()
    }
    function Get-Gzip([byte[]]$Body) {
        $Out = [System.IO.MemoryStream]::new()
        $Zip = [System.IO.Compression.GZipStream]::new($Out, [System.IO.Compression.CompressionMode]::Compress)
        $Zip.Write($Body, 0, $Body.Length); $Zip.Dispose()
        $Out.ToArray()
    }
    Set-Response 'gzip' 'application/json' (Get-Gzip ([System.Text.Encoding]::UTF8.GetBytes('{"zipped":true}'))) 'gzip'
}

AfterAll {
    $script:Listener.Stop()
    $script:Server.Dispose()
}

Describe 'CIPPRestClient response bodies' {
    It 'reads the <Name> body as ReadAsStringAsync does' -ForEach $Cases {
        Set-Response $Name $ContentType $Body
        $Result = [CIPP.CIPPRestClient]::Send("http://127.0.0.1:$script:Port/$Name", 'GET', $null, $null, $null, $true)
        $Expected = Get-Expected $ContentType $Body

        $Result.Content | Should -BeExactly $Expected
        $Result.HasContent | Should -Be (-not [string]::IsNullOrWhiteSpace($Expected))
        $Result.IsJson | Should -Be ("$ContentType" -like '*application/json*' -or $Expected.TrimStart().StartsWith('{') -or $Expected.TrimStart().StartsWith('['))
    }

    It 'parses the <Name> body from its bytes as ConvertFromJson does from the text' -ForEach $JsonCases {
        Set-Response $Name $ContentType $Body
        $Result = [CIPP.CIPPRestClient]::Send("http://127.0.0.1:$script:Port/$Name", 'GET', $null, $null, $null, $true)
        $Expected = [CIPP.CippJson]::ConvertFromJson((Get-Expected $ContentType $Body))

        ConvertTo-Json -InputObject ([CIPP.CippJson]::ConvertFromResponse($Result)) -Depth 10 -Compress | Should -BeExactly (ConvertTo-Json -InputObject $Expected -Depth 10 -Compress)
    }

    It 'keeps the UTF-8 bytes and reads text only for another charset' {
        Set-Response 'json' 'application/json' ([System.Text.Encoding]::UTF8.GetBytes('{"a":1}'))
        Set-Response 'utf16' 'application/json; charset=utf-16' ([System.Text.Encoding]::Unicode.GetBytes('{"a":1}'))
        ([CIPP.CIPPRestClient]::Send("http://127.0.0.1:$script:Port/json", 'GET', $null, $null, $null, $true)).ContentBytes | Should -Not -BeNullOrEmpty
        ([CIPP.CIPPRestClient]::Send("http://127.0.0.1:$script:Port/utf16", 'GET', $null, $null, $null, $true)).ContentBytes | Should -BeNullOrEmpty
    }

    It 'decodes a gzip body the handler left encoded' {
        $Result = [CIPP.CIPPRestClient]::Send("http://127.0.0.1:$script:Port/gzip", 'GET', $null, $null, $null, $true)
        $Result.Content | Should -BeExactly '{"zipped":true}'
        ([CIPP.CippJson]::ConvertFromResponse($Result)).zipped | Should -BeTrue
    }
}
