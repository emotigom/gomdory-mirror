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
$script:LastDeviceSerial = ''
$script:LastStatusKey = ''
$script:IsClosing = $false

function ConvertTo-XamlSafeText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Invoke-Adb {
    param([string[]]$Arguments)

    if (-not (Test-Path -LiteralPath $script:AdbPath)) {
        return [pscustomobject]@{ ExitCode = 127; Output = ''; Error = 'ADB 실행 파일 없음' }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:AdbPath
    $startInfo.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if (-not $process.WaitForExit(3500)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{ ExitCode = 124; Output = ''; Error = 'ADB 응답 시간 초과' }
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $process.StandardOutput.ReadToEnd().Trim()
            Error = $process.StandardError.ReadToEnd().Trim()
        }
    }
    catch {
        return [pscustomobject]@{ ExitCode = 1; Output = ''; Error = $_.Exception.Message }
    }
}

function Get-AndroidDevices {
    $result = Invoke-Adb -Arguments @('devices', '-l')
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{ Error = $result.Error; Devices = @() }
    }

    $devices = @()
    foreach ($line in ($result.Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -like 'List of devices*' -or $line -like '*daemon*') {
            continue
        }
        if ($line -match '^([^\s]+)\s+([^\s]+)(?:\s+(.*))?$') {
            $serial = $Matches[1]
            $state = $Matches[2]
            $details = $Matches[3]
            $model = ''
            if ($details -match '(?:^|\s)model:([^\s]+)') {
                $model = $Matches[1] -replace '_', ' '
            }
            $devices += [pscustomobject]@{
                Serial = $serial
                State = $state
                Model = $model
                Details = $details
            }
        }
    }
    return [pscustomobject]@{ Error = ''; Devices = @($devices) }
}

function Get-ConnectionState {
    if (-not (Test-Path -LiteralPath $script:ScrcpyPath) -or -not (Test-Path -LiteralPath $script:AdbPath)) {
        return [pscustomobject]@{
            Key = 'engine-missing'; Title = '실행 엔진을 찾을 수 없습니다';
            Detail = '배포용 ZIP을 다시 내려받아 압축을 완전히 풀어 주세요.';
            Color = '#B91C1C'; Action = '배포 파일 확인'; Device = $null
        }
    }

    $scan = Get-AndroidDevices
    if (-not [string]::IsNullOrWhiteSpace($scan.Error)) {
        return [pscustomobject]@{
            Key = 'adb-error'; Title = 'USB 연결을 확인하지 못했습니다';
            Detail = '케이블을 다시 꽂은 뒤 다시 확인해 주세요. 계속되면 진단 기록을 복사해 주세요.';
            Color = '#B91C1C'; Action = '다시 확인'; Device = $null
        }
    }

    $all = @($scan.Devices)
    if ($all.Count -eq 0) {
        return [pscustomobject]@{
            Key = 'no-device'; Title = '태블릿 연결을 기다리고 있습니다';
            Detail = '데이터 전송이 가능한 USB 케이블로 태블릿을 연결해 주세요.';
            Color = '#6B7280'; Action = '연결 방법 보기'; Device = $null
        }
    }

    $authorized = @($all | Where-Object { $_.State -eq 'device' })
    $unauthorized = @($all | Where-Object { $_.State -eq 'unauthorized' })
    $offline = @($all | Where-Object { $_.State -eq 'offline' })

    if ($authorized.Count -gt 1) {
        return [pscustomobject]@{
            Key = 'multiple'; Title = 'Android 기기가 여러 대 연결되어 있습니다';
            Detail = '수업에 사용할 태블릿 한 대만 남기고 다른 기기의 USB 케이블을 빼 주세요.';
            Color = '#B45309'; Action = '다시 확인'; Device = $null
        }
    }
    if ($authorized.Count -eq 1) {
        $device = $authorized[0]
        $name = if ([string]::IsNullOrWhiteSpace($device.Model)) { 'Android 태블릿' } else { $device.Model }
        return [pscustomobject]@{
            Key = 'ready'; Title = "$name 연결 준비 완료";
            Detail = '주강사는 태블릿을 그대로 조작하세요. 이 노트북은 화면만 TV로 전달합니다.';
            Color = '#15803D'; Action = '화면 연결'; Device = $device
        }
    }
    if ($unauthorized.Count -gt 0) {
        return [pscustomobject]@{
            Key = 'unauthorized'; Title = '태블릿에서 연결을 허용해 주세요';
            Detail = '태블릿 잠금을 풀고 “이 컴퓨터에서 항상 허용”을 선택한 뒤 허용을 누르세요.';
            Color = '#B45309'; Action = '승인 후 다시 확인'; Device = $unauthorized[0]
        }
    }
    if ($offline.Count -gt 0) {
        return [pscustomobject]@{
            Key = 'offline'; Title = '태블릿이 응답하지 않습니다';
            Detail = '태블릿 잠금을 해제하고 케이블을 한 번 뺐다가 다시 연결해 주세요.';
            Color = '#B45309'; Action = '다시 확인'; Device = $offline[0]
        }
    }
    return [pscustomobject]@{
        Key = 'unsupported-state'; Title = '태블릿 연결 상태를 확인해 주세요';
        Detail = 'USB 모드를 파일 전송으로 바꾸고 USB 디버깅이 켜져 있는지 확인하세요.';
        Color = '#B45309'; Action = '다시 확인'; Device = $all[0]
    }
}

function Get-QualityArguments {
    param([string]$Quality)
    switch ($Quality) {
        '선명하게' { return @('--max-size=2560', '--video-bit-rate=12M', '--max-fps=30') }
        '빠르게' { return @('--max-size=1280', '--video-bit-rate=4M', '--max-fps=30') }
        default { return @('--max-size=1920', '--video-bit-rate=8M', '--max-fps=30') }
    }
}

function Start-Mirror {
    param($Device)

    if ($null -eq $Device) { return }
    if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) {
        $script:MirrorProcess.Refresh()
        return
    }

    $arguments = @(
        '--serial', $Device.Serial,
        '--window-title', '곰도리 미러 · 수업 화면',
        '--stay-awake',
        '--disable-screensaver',
        '--no-control'
    )
    $arguments += Get-QualityArguments -Quality ([string]$QualityCombo.SelectedItem.Content)
    if ($FullscreenCheck.IsChecked) { $arguments += '--fullscreen' }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:ScrcpyPath
    $startInfo.WorkingDirectory = $script:EnginePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = ($arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '

    try {
        $script:MirrorProcess = [System.Diagnostics.Process]::Start($startInfo)
        $script:LastDeviceSerial = $Device.Serial
        $StatusTitle.Text = '수업 화면을 전송하고 있습니다'
        $StatusDetail.Text = '주강사는 태블릿을 직접 조작하세요. 연결을 끝내려면 아래 버튼을 누르세요.'
        $StatusDot.Fill = '#15803D'
        $PrimaryButton.Content = '연결됨'
        $PrimaryButton.IsEnabled = $false
        $StopButton.Visibility = 'Visible'
        Add-DiagnosticLine "미러링 시작: $($Device.Model) / $($Device.Serial)"
    }
    catch {
        Add-DiagnosticLine "미러링 실행 실패: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            '미러링을 시작하지 못했습니다. 진단 기록을 복사해 확인해 주세요.',
            '곰도리 미러', 'OK', 'Error'
        ) | Out-Null
    }
}

function Stop-Mirror {
    $AutoConnectCheck.IsChecked = $false
    if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) {
        try { $script:MirrorProcess.CloseMainWindow() | Out-Null } catch { }
        Start-Sleep -Milliseconds 250
        if (-not $script:MirrorProcess.HasExited) {
            try { $script:MirrorProcess.Kill() } catch { }
        }
        Add-DiagnosticLine '미러링 종료'
    }
    $script:MirrorProcess = $null
    $StopButton.Visibility = 'Collapsed'
    Update-ConnectionState -AllowAutoStart:$false
}

function Add-DiagnosticLine {
    param([string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $DiagnosticBox.AppendText("[$timestamp] $Message`r`n")
    $DiagnosticBox.ScrollToEnd()
}

function Update-ConnectionState {
    param([bool]$AllowAutoStart = $true)

    if ($script:IsClosing) { return }
    if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) { return }
    if ($script:MirrorProcess -and $script:MirrorProcess.HasExited) {
        $script:MirrorProcess = $null
        $StopButton.Visibility = 'Collapsed'
        Add-DiagnosticLine '미러링 창이 닫혔습니다.'
    }

    $state = Get-ConnectionState
    $StatusTitle.Text = $state.Title
    $StatusDetail.Text = $state.Detail
    $StatusDot.Fill = $state.Color
    $PrimaryButton.Content = $state.Action
    $PrimaryButton.Tag = $state
    $PrimaryButton.IsEnabled = $true

    if ($state.Key -ne $script:LastStatusKey) {
        Add-DiagnosticLine "상태: $($state.Key)"
        $script:LastStatusKey = $state.Key
    }

    if ($state.Key -eq 'ready' -and $AutoConnectCheck.IsChecked -and $AllowAutoStart) {
        Start-Mirror -Device $state.Device
    }
}

function Show-SetupGuide {
    $guide = @'
처음 한 번만 태블릿에서 설정합니다.

1. 설정 → 태블릿 정보 → 소프트웨어 정보
2. 빌드번호를 빠르게 7번 누르기
3. 설정 → 개발자 옵션 → USB 디버깅 켜기
4. 데이터 전송용 USB 케이블로 노트북 연결
5. 태블릿에서 “이 컴퓨터에서 항상 허용” 선택

※ 충전 전용 케이블은 사용할 수 없습니다.
※ 학교에서 관리하는 태블릿은 개발자 옵션이 차단될 수 있습니다.
'@
    [System.Windows.MessageBox]::Show($guide, '처음 연결하는 방법', 'OK', 'Information') | Out-Null
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="곰도리 미러" Width="760" Height="650" MinWidth="680" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#F7F5F0" FontFamily="Malgun Gothic">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="18,11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Background" Value="#274C43"/>
      <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="#374151"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>
  <Grid Margin="34,28,34,24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="18"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="18"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="16"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="곰도리 미러" FontSize="30" FontWeight="Bold" Foreground="#1F3A35"/>
        <TextBlock Text="케이블로 태블릿 화면을 TV에 안정적으로" Margin="0,6,0,0" FontSize="15" Foreground="#66736F"/>
      </StackPanel>
      <Border Grid.Column="1" Background="#E6EFEA" Padding="10,6" VerticalAlignment="Top">
        <TextBlock Text="PORTABLE 0.1" FontSize="12" FontWeight="Bold" Foreground="#315E52"/>
      </Border>
    </Grid>

    <Border Grid.Row="2" Background="White" BorderBrush="#DDD8CE" BorderThickness="1" Padding="24">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="14"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Ellipse x:Name="StatusDot" Width="18" Height="18" Fill="#6B7280" VerticalAlignment="Top" Margin="0,4,0,0"/>
        <StackPanel Grid.Column="2">
          <TextBlock x:Name="StatusTitle" Text="연결 상태를 확인하고 있습니다" FontSize="20" FontWeight="Bold" Foreground="#1F2937"/>
          <TextBlock x:Name="StatusDetail" Text="잠시만 기다려 주세요." Margin="0,9,0,0" FontSize="14" Foreground="#4B5563" TextWrapping="Wrap" LineHeight="22"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="4">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <CheckBox x:Name="AutoConnectCheck" Content="케이블 연결 시 자동 시작" IsChecked="True"/>
        <CheckBox x:Name="FullscreenCheck" Content="TV 전체 화면으로 열기" IsChecked="True" Margin="0,12,0,0"/>
        <TextBlock Text="화면 조작은 주강사의 태블릿에서만 가능합니다." Margin="0,12,0,0" FontSize="12" Foreground="#6B7280"/>
      </StackPanel>
      <StackPanel Grid.Column="2" Width="150">
        <TextBlock Text="화질" FontSize="13" Foreground="#4B5563" Margin="0,0,0,5"/>
        <ComboBox x:Name="QualityCombo" SelectedIndex="1" FontSize="14" Padding="8,6">
          <ComboBoxItem Content="빠르게"/>
          <ComboBoxItem Content="균형 있게"/>
          <ComboBoxItem Content="선명하게"/>
        </ComboBox>
      </StackPanel>
    </Grid>

    <Border Grid.Row="6" Background="#EFECE5" Padding="16" BorderBrush="#DDD8CE" BorderThickness="1">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="현장 진단 기록" FontSize="13" FontWeight="Bold" Foreground="#4B5563"/>
        <TextBox x:Name="DiagnosticBox" Grid.Row="1" Margin="0,9,0,9" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                 Background="#FAF9F6" BorderBrush="#D6D1C8" FontFamily="Consolas" FontSize="11" Foreground="#374151" Padding="8"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="GuideButton" Content="처음 연결하는 방법" Background="#6B7280" Padding="12,7" FontSize="12"/>
          <Button x:Name="DriverButton" Content="Samsung USB 드라이버" Background="#6B7280" Padding="12,7" FontSize="12" Margin="8,0,0,0"/>
          <Button x:Name="CopyLogButton" Content="기록 복사" Background="#6B7280" Padding="12,7" FontSize="12" Margin="8,0,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="7" Margin="0,18,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions>
      <Button x:Name="StopButton" Content="연결 끊기" Background="#9F3A38" Visibility="Collapsed"/>
      <Button x:Name="PrimaryButton" Grid.Column="2" Content="다시 확인"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$controlNames = @(
    'StatusDot', 'StatusTitle', 'StatusDetail', 'AutoConnectCheck', 'FullscreenCheck',
    'QualityCombo', 'DiagnosticBox', 'GuideButton', 'DriverButton', 'CopyLogButton',
    'StopButton', 'PrimaryButton'
)
foreach ($controlName in $controlNames) {
    Set-Variable -Name $controlName -Value $window.FindName($controlName) -Scope Script
}

$PrimaryButton.Add_Click({
    $state = $PrimaryButton.Tag
    if ($null -eq $state) { Update-ConnectionState; return }
    if ($state.Key -eq 'ready') { Start-Mirror -Device $state.Device; return }
    if ($state.Key -eq 'no-device' -or $state.Key -eq 'engine-missing') { Show-SetupGuide; return }
    Update-ConnectionState
})
$StopButton.Add_Click({ Stop-Mirror })
$GuideButton.Add_Click({ Show-SetupGuide })
$DriverButton.Add_Click({ Start-Process 'https://developer.samsung.com/android-usb-driver' })
$CopyLogButton.Add_Click({
    [System.Windows.Clipboard]::SetText($DiagnosticBox.Text)
    $CopyLogButton.Content = '복사됨'
})

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(1.5)
$timer.Add_Tick({ Update-ConnectionState })

$window.Add_ContentRendered({
    Add-DiagnosticLine "곰도리 미러 시작 / Windows $([Environment]::OSVersion.Version)"
    Update-ConnectionState
    $timer.Start()
})
$window.Add_Closing({
    $script:IsClosing = $true
    $timer.Stop()
    if ($script:MirrorProcess -and -not $script:MirrorProcess.HasExited) {
        try { $script:MirrorProcess.Kill() } catch { }
    }
})

$window.ShowDialog() | Out-Null
