import { image } from '@kit.ImageKit';
import { Any } from '@ohos/flutter_ohos';
import { AMap, Marker, MarkerOptions, LatLng, BitmapDescriptor, BitmapDescriptorFactory } from '@amap/amap_lbs_map3d';

class MarkerEntry {
  readonly marker: Marker;
  readonly icon: BitmapDescriptor;
  readonly bytes: Uint8Array;
  readonly width: number;
  readonly height: number;
  constructor(marker: Marker, icon: BitmapDescriptor, bytes: Uint8Array, width: number, height: number) {
    this.marker = marker; this.icon = icon; this.bytes = bytes; this.width = width; this.height = height;
  }
}
class PreparedMarker {
  readonly bytes: Uint8Array;
  readonly width: number;
  readonly height: number;
  readonly options: MarkerOptions;
  readonly icon: BitmapDescriptor;
  constructor(options: MarkerOptions, icon: BitmapDescriptor, bytes: Uint8Array, width: number, height: number) {
    this.options = options; this.icon = icon; this.bytes = bytes; this.width = width; this.height = height;
  }
}
export class MarkerStore {
  private entries: Map<string, MarkerEntry> = new Map();
  idFor(marker: Marker): string | null {
    for (const pair of this.entries) {
      if (pair[1].marker.getId() === marker.getId()) return pair[0];
    }
    return null;
  }
  apply(map: AMap, args: Map<string, Any>): void {
    const upsert: Array<Map<string, Any>> = args.get('upsert') as Array<Map<string, Any>>;
    const remove: Array<string> = args.get('remove') as Array<string>;
    if (!Array.isArray(upsert) || !Array.isArray(remove)) throw new Error('invalid_argument');
    const prepared: Map<string, PreparedMarker> = new Map<string, PreparedMarker>();
    remove.forEach((id: string) => { if (typeof id !== 'string') throw new Error('invalid_argument'); });
    const staged: Map<string, MarkerEntry> = new Map<string, MarkerEntry>();
    try {
      upsert.forEach((data: Map<string, Any>) => {
        const id = data.get('id') as string;
        if (typeof id !== 'string' || id.length === 0 || prepared.has(id) || remove.includes(id)) throw new Error('invalid_argument');
        const lat = this.number(data, 'latitude', -90, 90);
        const lng = this.number(data, 'longitude', -180, 180);
        const width = this.number(data, 'width', 0.000001, 512);
        const height = this.number(data, 'height', 0.000001, 512);
        const u = this.number(data, 'anchorU', 0, 1);
        const v = this.number(data, 'anchorV', 0, 1);
        const rotation = this.number(data, 'rotation', 0, 360);
        const z = this.number(data, 'zIndex', -1000000, 1000000);
        const visible = data.get('visible') as boolean;
        const bytes = data.get('pngBytes') as Uint8Array;
        if (typeof visible !== 'boolean' || rotation >= 360 || !Number.isInteger(z) || !(bytes instanceof Uint8Array) ||
          bytes.length < 8 || bytes.length > 4194304) throw new Error('invalid_argument');
        const signature: number[] = [137,80,78,71,13,10,26,10];
        for (let i = 0; i < 8; i++) { if (bytes[i] !== signature[i]) throw new Error('invalid_argument'); }
        const old = this.entries.get(id);
        let same = old !== undefined && old.width === width && old.height === height && old.bytes.length === bytes.length;
        if (same && old) { for (let i = 0; i < bytes.length; i++) { if (bytes[i] !== old.bytes[i]) { same = false; break; } } }
        if (same && old) {
          const options = new MarkerOptions().setPosition(new LatLng(lat, lng)).setIcon(old.icon)
            .setAnchor(u, v).setRotateAngle(-rotation).setZIndex(z).setVisible(visible);
          prepared.set(id, new PreparedMarker(options, old.icon, bytes, width, height));
          return;
        }
        const source = image.createImageSource(bytes.slice().buffer as ArrayBuffer);
        let pixel: image.PixelMap | null = null;
        try {
          const info = source.getImageInfoSync();
          if (info.size.width > 4096 || info.size.height > 4096) throw new Error('invalid_argument');
          pixel = source.createPixelMapSync({ desiredSize: {
            width: Math.max(1, Math.round(vp2px(width))), height: Math.max(1, Math.round(vp2px(height))) } });
          const icon = BitmapDescriptorFactory.fromPixelMapSync(pixel);
          if (!icon) throw new Error('native_error');
          const options = new MarkerOptions().setPosition(new LatLng(lat, lng)).setIcon(icon)
            .setAnchor(u, v).setRotateAngle(-rotation).setZIndex(z).setVisible(visible);
          prepared.set(id, new PreparedMarker(options, icon, bytes, width, height));
        } finally {
          pixel?.release();
          source.release();
        }
      });
      prepared.forEach((item: PreparedMarker, id: string) => {
        const marker = map.addMarker(item.options);
        if (!marker) throw new Error('native_error');
        staged.set(id, new MarkerEntry(marker, item.icon, item.bytes, item.width, item.height));
      });
      staged.forEach((entry: MarkerEntry, id: string) => {
        const old = this.entries.get(id);
        old?.marker.remove();
        if (old && old.icon !== entry.icon) old.icon.recycle();
        this.entries.set(id, entry);
      });
      remove.forEach((id: string) => {
        if (typeof id !== 'string') throw new Error('invalid_argument');
        const old = this.entries.get(id);
        old?.marker.remove();
        old?.icon.recycle();
        this.entries.delete(id);
      });
    } catch (error) {
      staged.forEach((entry: MarkerEntry, id: string) => {
        if (this.entries.get(id) !== entry) entry.marker.remove();
      });
      prepared.forEach((item: PreparedMarker, id: string) => {
        if (this.entries.get(id)?.icon !== item.icon) item.icon.recycle();
      });
      throw new Error((error as Error).message);
    }
  }
  private number(data: Map<string, Any>, key: string, min: number, max: number): number {
    const n = data.get(key) as number;
    if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max) throw new Error('invalid_argument');
    return n;
  }
  clear(): void {
    this.entries.forEach((entry: MarkerEntry) => { entry.marker.remove(); entry.icon.recycle(); });
    this.entries.clear();
  }
}
