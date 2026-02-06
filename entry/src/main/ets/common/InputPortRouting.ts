export enum InputSourceType {
  None = 0,
  Virtual = 1,
  Keyboard = 2,
  Mouse = 3,
  Gamepad = 4,
  BluetoothGamepad = 5,
  Unknown = 6
}

export interface InputDeviceInfo {
  deviceId: string;
  sourceType: InputSourceType;
  name: string;
}

export interface PortAssignState {
  portId: number;
  sourceType: InputSourceType;
  deviceId: string;
  isActive: boolean;
}

export function createDefaultPortAssignments(): PortAssignState[] {
  return [
    {
      portId: 0,
      sourceType: InputSourceType.Virtual,
      deviceId: '',
      isActive: true
    },
    {
      portId: 1,
      sourceType: InputSourceType.None,
      deviceId: '',
      isActive: false
    },
    {
      portId: 2,
      sourceType: InputSourceType.None,
      deviceId: '',
      isActive: false
    },
    {
      portId: 3,
      sourceType: InputSourceType.None,
      deviceId: '',
      isActive: false
    }
  ];
}

export function isVirtualSource(sourceType: InputSourceType): boolean {
  return sourceType === InputSourceType.Virtual;
}
