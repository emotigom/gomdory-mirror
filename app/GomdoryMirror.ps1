Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:RootPath = Split-Path -Parent $PSScriptRoot
$script:EnginePath = Join-Path $script:RootPath 'tools\scrcpy'
$script:AdbPath = Join-Path $script:EnginePath 'adb.exe'
$script:ScrcpyPath = Join-Path $script:EnginePath 'scrcpy.exe'
$script:MirrorProcess = $null
$script:MirrorStdOutTask = $null
$script:MirrorStdErrTask = $null
$script:LastAutoStartSerial = ''
$script:IsClosing = $false
$script:LogPath = Join-Path $env:LOCALAPPDATA 'GomdoryMirror\gomdory-mirror.log'

function Write-AppLog {
    param([string]$Message)
    try {
        $directory = Split-Path -Parent $script:LogPath
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        [System.IO.File]::AppendAllText($script:LogPath, "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message`r`n", [System.Text.UTF8Encoding]::new($false))
    }
    catch { }
}

function Add-DiagnosticLine {
    param([string]$Message)
    Write-AppLog $Message
    if ($null -ne $DiagnosticBox) {
        $DiagnosticBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n")
        $DiagnosticBox.ScrollToEnd()
    }
}

function Join-ProcessArguments {
    param([string[]]$Arguments)
    return (($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
}

function Invoke-Adb {
    param([string[]]$Arguments, [int]$TimeoutMilliseconds = 3500)
    if (-not (Test-Path -LiteralPath $script:AdbPath)) {
        return [pscustomobject]@{ ExitCode = 127; Output = ''; Error = 'ADB 실행 파일이 없습니다.' }
    }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:AdbPath
    $startInfo.Arguments = Join-ProcessArguments -Arguments $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill(); $process.WaitForExit() } catch { }
            return [pscustomobject]@{ ExitCode = 124; Output = ''; Error = '태블릿 연결 확인 시간이 초과되었습니다.' }
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result.Trim(); Error = $stderr.Result.Trim() }
    }
    catch { return [pscustomobject]@{ ExitCode = 1; Output = ''; Error = $_.Exception.Message } }
    finally { if ($null -ne $process) { $process.Dispose() } }
}

function Get-AndroidDevices {
    $result = Invoke-Adb -Arguments @('devices', '-l')
    if ($result.ExitCode -ne 0) {
        $message = @($result.Error, $result.Output) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return [pscustomobject]@{ Error = ($message -join ' / '); Devices = @() }
    }
    $devices = @()
    foreach ($line in ($result.Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -like 'List of devices*' -or $line -like '*daemon*') { continue }
        if ($line -match '^([^\s]+)\s+([^\s]+)(?:\s+(.*))?$') {
            $model = ''
            if ($Matches[3] -match '(?:^|\s)model:([^\s]+)') { $model = $Matches[1] -replace '_', ' ' }
            $devices += [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2]; Model = $model }
        }
    }
    return [pscustomobject]@{ Error = ''; Devices = @($devices) }
}

function Get-ConnectionState {
    if (-not (Test-Path -LiteralPath $script:ScrcpyPath) -or -not (Test-Path -LiteralPath $script:AdbPath)) {
        return [pscustomobject]@{ Key = 'engine-missing'; Title = '실행 파일을 찾지 못했습니다'; Detail = 'ZIP을 완전히 푼 뒤 폴더 안의 “곰도리 미러 시작.cmd”를 실행해 주세요.'; Color = '#B91C1C'; Action = '연결 방법'; Device = $null }
    }
    $scan = Get-AndroidDevices
    if (-not [string]::IsNullOrWhiteSpace($scan.Error)) {
        return [pscustomobject]@{ Key = 'adb-error'; Title = '태블릿 연결을 확인하지 못했습니다'; Detail = '케이블을 다시 연결한 뒤 “다시 확인”을 누르세요.'; Color = '#B91C1C'; Action = '다시 확인'; Device = $null; Diagnostic = $scan.Error }
    }
    $ready = @($scan.Devices | Where-Object { $_.State -eq 'device' })
    $unauthorized = @($scan.Devices | Where-Object { $_.State -eq 'unauthorized' })
    $offline = @($scan.Devices | Where-Object { $_.State -eq 'offline' })
    if ($ready.Count -gt 1) {
        return [pscustomobject]@{ Key = 'multiple'; Title = '태블릿이 여러 대 연결되어 있습니다'; Detail = '수업에 쓸 태블릿 하나만 남기고 다른 Android 기기의 USB 케이블을 빼 주세요.'; Color = '#B45309'; Action = '다시 확인'; Device = $null }
    }
    if ($ready.Count -eq 1) {
        $device = $ready[0]
        $name = if ([string]::IsNullOrWhiteSpace($device.Model)) { '태블릿' } else { $device.Model }
        return [pscustomobject]@{ Key = 'ready'; Title = "$name 연결 완료"; Detail = '이제 “화면 열기”를 누르세요. 주강사는 태블릿을 직접 조작합니다.'; Color = '#15803D'; Action = '화면 열기'; Device = $device }
    }
    if ($unauthorized.Count -gt 0) {
        return [pscustomobject]@{ Key = 'unauthorized'; Title = '태블릿에서 USB 디버깅을 허용해 주세요'; Detail = '태블릿 잠금을 풀고 “이 컴퓨터에서 항상 허용”을 체크한 뒤 허용을 누르세요.'; Color = '#B45309'; Action = '허용 후 다시 확인'; Device = $unauthorized[0] }
    }
    if ($offline.Count -gt 0) {
        return [pscustomobject]@{ Key = 'offline'; Title = '태블릿이 응답하지 않습니다'; Detail = '태블릿 잠금을 해제하고 케이블을 한 번 뺐다가 다시 연결해 주세요.'; Color = '#B45309'; Action = '다시 확인'; Device = $offline[0] }
    }
    return [pscustomobject]@{ Key = 'no-device'; Title = '태블릿을 연결해 주세요'; Detail = '데이터 전송이 가능한 USB 케이블을 연결하고, 처음이면 USB 디버깅을 허용해 주세요.'; Color = '#6B7280'; Action = '연결 방법'; Device = $null }
}

function Get-QualityArguments {
    switch ([string]$QualityCombo.SelectedItem.Content) {
        '빠르게' { return @('--max-size=1280', '--video-bit-rate=4M', '--max-fps=30') }
        '선명하게' { return @('--max-size=2560', '--video-bit-rate=12M', '--max-fps=30') }
        default { return @('--max-size=1920', '--video-bit-rate=8M', '--max-fps=30') }
    }
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    try { $Process.Refresh() } catch { return }
    if ($Process.HasExited) { return }
    try { $Process.CloseMainWindow() | Out-Null } catch { }
    if ($Process.WaitForExit(1000)) { return }
    try {
        $taskKill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $killer = Start-Process -FilePath $taskKill -ArgumentList @('/PID', "$($Process.Id)", '/T', '/F') -NoNewWindow -PassThru
        $killer.WaitForExit(3000) | Out-Null
    }
    catch { try { $Process.Kill() } catch { } }
}

function Restore-ControlWindow {
    if ($script:IsClosing) { return }
    if (-not $window.IsVisible) { $window.Show() }
    $window.Activate()
}

function Add-MirrorExitDiagnostics {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    Add-DiagnosticLine "화면 전송이 끝났습니다. (종료 코드: $($Process.ExitCode))"
    foreach ($task in @($script:MirrorStdOutTask, $script:MirrorStdErrTask)) {
        if ($null -eq $task) { continue }
        try {
            ($task.Result -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 8) | ForEach-Object { Add-DiagnosticLine "scrcpy: $($_.Trim())" }
        }
        catch { Add-DiagnosticLine "scrcpy 기록을 읽지 못했습니다: $($_.Exception.Message)" }
    }
    $script:MirrorStdOutTask = $null
    $script:MirrorStdErrTask = $null
}

function WaitForMirrorWindow {
    param([System.Diagnostics.Process]$Process)
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 150
        try {
            $Process.Refresh()
            if ($Process.HasExited) { return $false }
            if ($Process.MainWindowHandle -ne [IntPtr]::Zero) { return $true }
        }
        catch { return $false }
    }
    return -not $Process.HasExited
}

function Start-Mirror {
    param($Device)
    if ($null -eq $Device) { return }
    if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) { return }
    $arguments = @("--serial=$($Device.Serial)", '--window-title=곰도리 미러', '--no-control', '--no-audio', '--stay-awake', '--disable-screensaver')
    $arguments += Get-QualityArguments
    if ($FullscreenCheck.IsChecked) { $arguments += '--fullscreen' }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:ScrcpyPath
    $startInfo.WorkingDirectory = $script:EnginePath
    $startInfo.Arguments = Join-ProcessArguments -Arguments $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    try {
        $script:MirrorProcess = [System.Diagnostics.Process]::Start($startInfo)
        $script:MirrorStdOutTask = $script:MirrorProcess.StandardOutput.ReadToEndAsync()
        $script:MirrorStdErrTask = $script:MirrorProcess.StandardError.ReadToEndAsync()
        $script:LastAutoStartSerial = $Device.Serial
        $StatusTitle.Text = '화면을 열고 있습니다'
        $StatusDetail.Text = '화면 창이 준비되면 이 창은 자동으로 숨겨집니다.'
        $StatusDot.Fill = '#15803D'
        $PrimaryButton.IsEnabled = $false
        $StopButton.Visibility = 'Visible'
        Add-DiagnosticLine "화면 전송 시작: $($Device.Model)"
        if (WaitForMirrorWindow -Process $script:MirrorProcess) {
            # ShowDialog()가 아닌 일반 창이므로 Hide() 뒤에도 앱이 종료되지 않습니다.
            $window.Hide()
        }
    }
    catch {
        $script:MirrorProcess = $null
        Add-DiagnosticLine "화면 전송을 시작하지 못했습니다: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show('화면을 열지 못했습니다. “기록 복사”를 눌러 기록을 보내 주세요.', '곰도리 미러', 'OK', 'Error') | Out-Null
    }
}

function Stop-Mirror {
    $AutoConnectCheck.IsChecked = $false
    if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) {
        Stop-ProcessTree -Process $script:MirrorProcess
        try { $script:MirrorProcess.WaitForExit(2000) | Out-Null } catch { }
        if ($script:MirrorProcess.HasExited) { Add-MirrorExitDiagnostics -Process $script:MirrorProcess }
    }
    $script:MirrorProcess = $null
    $StopButton.Visibility = 'Collapsed'
    Restore-ControlWindow
    Refresh-Connection -AllowAutoStart:$false
}

function Refresh-Connection {
    param([bool]$AllowAutoStart = $true)
    if ($script:IsClosing) { return }
    if ($script:MirrorProcess) {
        try { $script:MirrorProcess.Refresh() } catch { }
        if (-not $script:MirrorProcess.HasExited) { return }
        Add-MirrorExitDiagnostics -Process $script:MirrorProcess
        $script:MirrorProcess = $null
        $StopButton.Visibility = 'Collapsed'
        Restore-ControlWindow
        $AutoConnectCheck.IsChecked = $false
        Add-DiagnosticLine '미러 창이 닫혔습니다. 필요하면 “화면 열기”를 다시 누르세요.'
    }
    $state = Get-ConnectionState
    $StatusTitle.Text = $state.Title
    $StatusDetail.Text = $state.Detail
    $StatusDot.Fill = $state.Color
    $PrimaryButton.Content = $state.Action
    $PrimaryButton.Tag = $state
    $PrimaryButton.IsEnabled = $true
    $diagnostic = $state.PSObject.Properties['Diagnostic']
    if ($null -ne $diagnostic) { Add-DiagnosticLine "ADB: $($diagnostic.Value)" }
    if ($state.Key -ne 'ready') { $script:LastAutoStartSerial = '' }
    if ($state.Key -eq 'ready' -and $AutoConnectCheck.IsChecked -and $AllowAutoStart -and $script:LastAutoStartSerial -ne $state.Device.Serial) { Start-Mirror -Device $state.Device }
}

function Show-SetupGuide {
    [System.Windows.MessageBox]::Show(@'
처음 한 번만 태블릿에서 설정합니다.

1. 설정 → 태블릿 정보 → 소프트웨어 정보 → 빌드번호 7번 누르기
2. 설정 → 개발자 옵션 → USB 디버깅 켜기
3. 데이터 전송용 USB 케이블로 노트북 연결
4. 태블릿에 뜨는 “이 컴퓨터에서 항상 허용”을 체크하고 허용

연결이 안 되면 충전 전용 케이블인지 먼저 확인해 주세요.
'@, '처음 연결하는 방법', 'OK', 'Information') | Out-Null
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="곰도리 미러" Width="620" Height="500" MinWidth="580" MinHeight="460" WindowStartupLocation="CenterScreen" Background="#F7F5F0" FontFamily="Malgun Gothic">
  <Grid Margin="32,28,32,24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="18"/><RowDefinition Height="Auto"/><RowDefinition Height="18"/><RowDefinition Height="Auto"/><RowDefinition Height="16"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0"><TextBlock Text="곰도리 미러" FontSize="30" FontWeight="Bold" Foreground="#1F3A35"/><TextBlock Text="태블릿을 케이블로 연결해 TV에 띄웁니다" Margin="0,6,0,0" FontSize="15" Foreground="#66736F"/></StackPanel>
    <Border Grid.Row="2" Background="White" BorderBrush="#DDD8CE" BorderThickness="1" Padding="22"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="22"/><ColumnDefinition Width="14"/><ColumnDefinition/></Grid.ColumnDefinitions><Ellipse x:Name="StatusDot" Width="16" Height="16" Fill="#6B7280" VerticalAlignment="Top" Margin="0,5,0,0"/><StackPanel Grid.Column="2"><TextBlock x:Name="StatusTitle" Text="연결 상태를 확인하고 있습니다" FontSize="20" FontWeight="Bold" Foreground="#1F2937"/><TextBlock x:Name="StatusDetail" Text="잠시만 기다려 주세요." Margin="0,8,0,0" FontSize="14" Foreground="#4B5563" TextWrapping="Wrap" LineHeight="22"/></StackPanel></Grid></Border>
    <Grid Grid.Row="4"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="18"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions><StackPanel><CheckBox x:Name="AutoConnectCheck" Content="다음부터 케이블 연결 시 자동으로 화면 열기" IsChecked="False" FontSize="13" Foreground="#374151"/><CheckBox x:Name="FullscreenCheck" Content="TV 전체 화면으로 열기" IsChecked="False" Margin="0,10,0,0" FontSize="13" Foreground="#374151"/><TextBlock Text="기본 창 모드에서는 미러 창의 X 한 번으로 종료합니다." Margin="0,10,0,0" FontSize="12" Foreground="#6B7280"/></StackPanel><StackPanel Grid.Column="2"><TextBlock Text="화질" FontSize="13" Foreground="#4B5563" Margin="0,0,0,5"/><ComboBox x:Name="QualityCombo" SelectedIndex="1" FontSize="14" Padding="8,6"><ComboBoxItem Content="빠르게"/><ComboBoxItem Content="균형 있게"/><ComboBoxItem Content="선명하게"/></ComboBox></StackPanel></Grid>
    <Expander Grid.Row="6" Header="문제가 있을 때만 열기 · 진단 기록" Foreground="#4B5563" FontSize="13"><Grid Margin="0,10,0,0"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBox x:Name="DiagnosticBox" MinHeight="105" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#FAF9F6" BorderBrush="#D6D1C8" FontFamily="Consolas" FontSize="11" Foreground="#374151" Padding="8"/><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0"><Button x:Name="GuideButton" Content="처음 연결" Background="#6B7280" Foreground="White" Padding="11,6" BorderThickness="0"/><Button x:Name="DriverButton" Content="Samsung 드라이버" Background="#6B7280" Foreground="White" Padding="11,6" BorderThickness="0" Margin="8,0,0,0"/><Button x:Name="CopyLogButton" Content="기록 복사" Background="#6B7280" Foreground="White" Padding="11,6" BorderThickness="0" Margin="8,0,0,0"/></StackPanel></Grid></Expander>
    <Grid Grid.Row="7" Margin="0,18,0,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions><Button x:Name="StopButton" Content="연결 끊기" Background="#9F3A38" Foreground="White" Padding="16,10" BorderThickness="0" Visibility="Collapsed"/><Button x:Name="PrimaryButton" Grid.Column="2" Content="다시 확인" Background="#274C43" Foreground="White" Padding="16,10" BorderThickness="0"/></Grid>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in @('StatusDot','StatusTitle','StatusDetail','AutoConnectCheck','FullscreenCheck','QualityCombo','DiagnosticBox','GuideButton','DriverButton','CopyLogButton','StopButton','PrimaryButton')) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
$PrimaryButton.Add_Click({ $state = $PrimaryButton.Tag; if ($null -eq $state) { Refresh-Connection; return }; if ($state.Key -eq 'ready') { Start-Mirror -Device $state.Device; return }; if ($state.Key -eq 'no-device' -or $state.Key -eq 'engine-missing') { Show-SetupGuide; return }; Refresh-Connection })
$StopButton.Add_Click({ Stop-Mirror })
$GuideButton.Add_Click({ Show-SetupGuide })
$DriverButton.Add_Click({ Start-Process 'https://developer.samsung.com/android-usb-driver' })
$CopyLogButton.Add_Click({ [System.Windows.Clipboard]::SetText($DiagnosticBox.Text); $CopyLogButton.Content = '복사됨' })
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Refresh-Connection })
$window.Add_ContentRendered({ Add-DiagnosticLine "곰도리 미러 시작 / Windows $([Environment]::OSVersion.Version)"; Refresh-Connection -AllowAutoStart:$false; $timer.Start() })
$window.Add_Closed({ $script:IsClosing = $true; $timer.Stop(); if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) { Stop-ProcessTree -Process $script:MirrorProcess }; $window.Dispatcher.BeginInvokeShutdown([System.Windows.Threading.DispatcherPriority]::Normal) })
trap { Write-AppLog "치명적 오류: $($_.Exception.Message)"; try { [System.Windows.MessageBox]::Show("프로그램 오류가 기록되었습니다.`r`n$script:LogPath", '곰도리 미러', 'OK', 'Error') | Out-Null } catch { }; exit 1 }

# ShowDialog()를 사용하지 않습니다. 창을 숨겨도 메시지 루프가 살아 있어 미러 창이 닫힌 뒤 준비 창으로 안전하게 돌아옵니다.
$window.Show()
[System.Windows.Threading.Dispatcher]::Run()
