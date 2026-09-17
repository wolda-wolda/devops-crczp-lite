PROGRAM SubstationProtection
  VAR_INPUT
    GRID_HEALTH_OK AT %IX0.0 : BOOL;
  END_VAR
  VAR_OUTPUT
    CB_MAIN_CLOSED AT %QX0.0 : BOOL := TRUE;
    CAP_BANK_ENABLED AT %QX0.1 : BOOL := TRUE;
    ALARM_OVERVOLTAGE AT %QX0.2 : BOOL := FALSE;
  END_VAR
  VAR
    BUS632_VOLTAGE_V AT %MW0 : UINT := 2400;
    FEEDER_LOAD_KW AT %MW1 : UINT := 1500;
    TAP_CHANGER_POS AT %MW2 : INT := 0;
    GRID_FREQ_HZ AT %MW3 : UINT := 6000;
    INIT_DONE : BOOL := FALSE;
  END_VAR

  (* Initialize default coil outputs to TRUE on boot *)
  IF NOT INIT_DONE THEN
    CB_MAIN_CLOSED := TRUE;
    CAP_BANK_ENABLED := TRUE;
    ALARM_OVERVOLTAGE := FALSE;
    INIT_DONE := TRUE;
  END_IF;

  (* Over-voltage protection threshold check: 255.0V scaled x10 = 2550 *)
  IF BUS632_VOLTAGE_V > 2550 THEN
    ALARM_OVERVOLTAGE := TRUE;
    CB_MAIN_CLOSED := FALSE; (* Trip main breaker *)
  END_IF;

  (* Under-frequency trip protection: 58.50 Hz scaled x100 = 5850 *)
  IF GRID_FREQ_HZ > 0 AND GRID_FREQ_HZ < 5850 THEN
    CB_MAIN_CLOSED := FALSE; (* Trip main breaker *)
  END_IF;

END_PROGRAM

CONFIGURATION Config0
  RESOURCE Res0 ON PLC
    TASK TaskMain(INTERVAL := T#100ms, PRIORITY := 1);
    PROGRAM Inst0 WITH TaskMain : SubstationProtection;
  END_RESOURCE
END_CONFIGURATION
