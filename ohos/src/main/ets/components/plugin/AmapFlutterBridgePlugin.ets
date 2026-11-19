import ArrayList from '@ohos.util.ArrayList';
import { AMapSearchBridge } from './AMapSearchBridge';
import { MarkerStore } from './MarkerStore';
import { NodeRenderType } from '@kit.ArkUI';
import { DVModel, DVModelParameters } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView';
import { EmbeddingNodeController } from '@ohos/flutter_ohos/src/main/ets/embedding/ohos/EmbeddingNodeController';
import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel,
  MethodResult, BinaryMessenger, PlatformView, PlatformViewFactory, StandardMessageCodec,
  Any } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { common } from '@kit.AbilityKit';
import { MapsInitializer, MapView, MapViewComponent, MapViewManager, AMap,
  CameraUpdateFactory, LatLng, CameraPosition, OnCameraChangeListener, Marker, Polyline, PolylineOptions,
  Polygon, PolygonOptions, Point, Circle, CircleOptions, LatLngBounds, MapType } from '@amap/amap_lbs_map3d';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';

const VIEW_TYPE: string = 'dev.hscw.amap_flutter_bridge/map';

export default class AmapFlutterBridgePlugin implements FlutterPlugin, MethodCallHandler {
  private static configuredKey: string = '';
  private searchBridge: AMapSearchBridge = new AMapSearchBridge();
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private views: Map<number, AMapNativeView> = new Map();

  getUniqueClassName(): string { return 'AmapFlutterBridgePlugin'; }
  static isInitialized(): boolean { return AmapFlutterBridgePlugin.configuredKey.length > 0; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.searchBridge = new AMapSearchBridge();
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dev.hscw.amap_flutter_bridge/sdk');
    this.channel.setMethodCallHandler(this);
    binding.getPlatformViewRegistry().registerViewFactory(VIEW_TYPE,
      new AMapFactory(binding.getBinaryMessenger(), this.views));
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'activeMapCount') { result.success(this.views.size); return; }
    if (['reverseGeocode', 'forwardGeocode', 'searchPoi', 'searchPoiPage', 'inputTips', 'poiById'].includes(call.method)) {
      if (!this.context || !AmapFlutterBridgePlugin.isInitialized()) {
        result.error('sdk_not_initialized', null, null); return;
      }
      const key = AmapFlutterBridgePlugin.configuredKey;
      switch (call.method) {
        case 'reverseGeocode': this.searchBridge.lookup(this.context, key, call, result); break;
        case 'forwardGeocode': this.searchBridge.forwardGeocode(this.context, key, call, result); break;
        case 'inputTips': this.searchBridge.inputTips(this.context, key, call, result); break;
        case 'poiById': this.searchBridge.poiById(this.context, key, call, result); break;
        default: this.searchBridge.searchPoi(this.context, key, call, result);
      }
      return;
    }
    if (call.method !== 'initialize') { result.notImplemented(); return; }
    const key: string = call.argument('apiKey') as string;
    if (call.argument('privacyAgreed') !== true) {
      result.error('privacy_not_agreed', 'Consent required', null); return;
    }
    if (!key || key.trim().length === 0) {
      result.error('invalid_argument', 'Key required', null); return;
    }
    if (AmapFlutterBridgePlugin.configuredKey && AmapFlutterBridgePlugin.configuredKey !== key) {
      result.error('initialization_conflict', 'Key already configured', null); return;
    }
    if (!this.context) { result.error('native_error', 'Engine detached', null); return; }
    try {
      if (!AmapFlutterBridgePlugin.configuredKey) {
        MapsInitializer.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, this.context);
        MapsInitializer.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, this.context);
        MapsInitializer.setApiKey(key);
        MapsInitializer.initialize(this.context);
        AmapFlutterBridgePlugin.configuredKey = key;
      }
      result.success(MapsInitializer.getVersion());
    } catch (_) { result.error('native_error', 'SDK initialization failed', null); }
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    Array.from(this.views.values()).forEach((view: AMapNativeView) => view.requestDisposal());
    this.searchBridge.dispose();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }
}

class AMapFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;
  private views: Map<number, AMapNativeView>;
  constructor(messenger: BinaryMessenger, views: Map<number, AMapNativeView>) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
    this.views = views;
  }
  create(_context: common.Context, id: number, args: Any): PlatformView {
    const view = new AMapNativeView(this.messenger, id, args as Map<string, Any>, () => this.views.delete(id));
    this.views.set(id, view);
    return view;
  }
}

enum ScreenAnchorMode {
  sdkDefault,
  custom,
  centered
}

class AMapNativeView extends PlatformView implements MethodCallHandler {
  private displayModel: DVModel | null = null;
  layout: DVModelParameters = new DVModelParameters();
  readonly name: string;
  readonly valid: boolean;
  private channel: MethodChannel;
  private nativeView: MapView | null = null;
  private circles: Map<string, Circle> = new Map();
  private polylines: Map<string, Polyline> = new Map();
  private polygons: Map<string, Polygon> = new Map();
  private markers: MarkerStore = new MarkerStore();
  private map: AMap | null = null;
  private status: string = 'creating';
  private disposed: boolean = false;
  private screenAnchorMode: ScreenAnchorMode = ScreenAnchorMode.sdkDefault;
  private released: boolean = false;
  private registered: boolean = false;
  private active: boolean = false;
  private visible: boolean = true;
  private latitude: number;
  private longitude: number;
  private zoom: number;
  private directDragEnabled: boolean = false;
  private trackingDrag: boolean = false;
  private dragging: boolean = false;
  private dragX: number = 0;
  private dragY: number = 0;
  private createdCallback = (view?: MapView, name?: string): void => {
    if (this.disposed || name !== this.name || !view) return;
    this.nativeView = view;
    try {
      view.onCreate();
      view.getMapAsync((map: AMap) => {
        if (this.disposed) return;
        try {
          this.map = map;
          map.setOnMapTouchListener((event: TouchEvent): void => {
            if (!this.disposed) this.handleCameraTouch(map, event);
          });
          map.setOnMapClickListener((point: LatLng): void => {
            if (!this.disposed) {
              this.channel.invokeMethod('mapTap', new Map<string, Any>([
                ['latitude', point.latitude], ['longitude', point.longitude]
              ]));
            }
          });
          map.setOnMarkerClickListener((marker: Marker): boolean => {
            const id = this.markers.idFor(marker);
            if (!this.disposed && id !== null) this.channel.invokeMethod('markerTap', id);
            return true;
          });
          map.setMinZoomLevel(3);
          map.setMaxZoomLevel(20);
          map.addOnCameraChangeListener(new OnCameraChangeListener(
            (position: CameraPosition) => this.cameraEvent('cameraMove', position),
            (position: CameraPosition) => this.cameraEvent('cameraIdle', position)));
          // The immediate ready event precedes getMapAsync; use the SDK's delayed load event.
          map.addOnMapReadyDelayListener((_map: AMap) => this.update('loaded'));
          map.moveCamera(CameraUpdateFactory.newLatLngZoom(new LatLng(this.latitude, this.longitude), this.zoom));
          this.update('ready');
          if (this.active && this.visible) view.onResume();
        } catch (_) { this.update('failed'); }
      });
    } catch (_) { this.update('failed'); }
  };

  private onDisposed: () => void;
  constructor(messenger: BinaryMessenger, id: number, args: Map<string, Any>, onDisposed: () => void) {
    super();
    this.onDisposed = onDisposed;
    this.name = `amap_flutter_${id}_${Date.now()}`;
    this.channel = new MethodChannel(messenger, `${VIEW_TYPE}/${id}`);
    this.channel.setMethodCallHandler(this);
    this.active = args.get('active') === true;
    this.latitude = args.get('latitude') as number;
    this.longitude = args.get('longitude') as number;
    this.zoom = args.get('zoom') as number;
    this.valid = AmapFlutterBridgePlugin.isInitialized() && args.get('protocolVersion') === 1 &&
      Number.isFinite(this.latitude) && Math.abs(this.latitude) <= 90 &&
      Number.isFinite(this.longitude) && Math.abs(this.longitude) <= 180 &&
      Number.isFinite(this.zoom) && this.zoom >= 3 && this.zoom <= 20;
    if (this.valid) {
      MapViewManager.getInstance().registerMapViewCreatedCallback(this.createdCallback);
      this.registered = true;
    } else { this.status = 'failed'; }
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'updateMarkers') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      if (!this.map || this.status === 'failed') { result.error('map_not_ready', null, null); return; }
      try {
        this.markers.apply(this.map, call.args as Map<string, Any>);
        result.success(null);
      } catch (error) {
        const message = (error as Error).message;
        result.error(message === 'invalid_argument' ? 'invalid_argument' : 'native_error', null, null);
      }
    }
    else if (call.method === 'updatePolylines') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      if (!this.map || this.status === 'failed') { result.error('map_not_ready', null, null); return; }
      try {
        this.updatePolylines(this.map, call.args as Map<string, Any>);
        result.success(null);
      } catch (error) {
        const message = (error as Error).message;
        result.error(message === 'invalid_argument' ? 'invalid_argument' : 'native_error', null, null);
      }
    }
    else if (call.method === 'updateCircles' || call.method === 'updatePolygons') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      if (!this.map || this.status === 'failed') { result.error('map_not_ready', null, null); return; }
      try {
        if (call.method === 'updatePolygons') this.updatePolygons(this.map, call.args as Map<string, Any>);
        else this.updateCircles(this.map, call.args as Map<string, Any>);
        result.success(null);
      } catch (error) {
        const message = (error as Error).message;
        result.error(message === 'invalid_argument' ? 'invalid_argument' : 'native_error', null, null);
      }
    }
    else if (call.method === 'setOptions') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      const map = this.map;
      if (!map || this.status === 'failed') { result.error('map_not_ready', null, null); return; }
      try {
        this.setOptions(map, call.args as Map<string, Any>);
        result.success(null);
      } catch (error) {
        const code = (error as Error).message;
        result.error(code === 'invalid_argument' || code === 'unsupported_option' ? code : 'native_error', null, null);
      }
    }
    else if (call.method === 'projectToScreen' || call.method === 'unprojectFromScreen') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      const layout = this.layout as Record<string, Any>;
      const width: number = layout['width'] as number;
      const height: number = layout['height'] as number;
      if (!this.map || this.status === 'failed' || !Number.isFinite(width) ||
          !Number.isFinite(height) || width <= 0 || height <= 0) {
        result.error('map_not_ready', null, null); return;
      }
      if (call.method === 'unprojectFromScreen') {
        const x = call.argument('x') as number;
        const y = call.argument('y') as number;
        if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x >= width || y >= height) {
          result.error('invalid_argument', null, null); return;
        }
        try {
          const point = new Point(Math.min(Math.round(vp2px(x)), Math.ceil(vp2px(width)) - 1),
            Math.min(Math.round(vp2px(y)), Math.ceil(vp2px(height)) - 1));
          const coordinate = this.map.getProjection()?.fromScreenLocationSync(point);
          if (!coordinate || !Number.isFinite(coordinate.latitude) || Math.abs(coordinate.latitude) > 90 ||
              !Number.isFinite(coordinate.longitude) || Math.abs(coordinate.longitude) > 180) {
            result.error('projection_failed', null, null); return;
          }
          result.success(new Map<string, Any>([['latitude', coordinate.latitude], ['longitude', coordinate.longitude]]));
        } catch (_) { result.error('projection_failed', null, null); }
        return;
      }
      const lat = call.argument('latitude') as number;
      const lng = call.argument('longitude') as number;
      if (!Number.isFinite(lat) || Math.abs(lat) > 90 || !Number.isFinite(lng) || Math.abs(lng) > 180) {
        result.error('invalid_argument', null, null); return;
      }
      try {
        const point = this.map.getProjection()?.toScreenLocationSync(new LatLng(lat, lng));
        if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) {
          result.error('projection_failed', null, null); return;
        }
        const projected: Map<string, Any> = new Map();
        projected.set('x', px2vp(point.x));
        projected.set('y', px2vp(point.y));
        result.success(projected);
      } catch (_) { result.error('projection_failed', null, null); }
    }
    else if (call.method === 'fitBounds') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      const map = this.map;
      const layout = this.layout as Record<string, Any>;
      const width: number = layout['width'] as number;
      const height: number = layout['height'] as number;
      if (!map || this.status === 'failed' || !Number.isFinite(width) ||
          !Number.isFinite(height) || width <= 0 || height <= 0) {
        result.error('map_not_ready', null, null); return;
      }
      try {
        this.fitBounds(map, call.args as Map<string, Any>, vp2px(width), vp2px(height));
        result.success(null);
      } catch (error) {
        const code = (error as Error).message === 'invalid_argument' ? 'invalid_argument' : 'native_error';
        result.error(code, null, null);
      }
    }
    else if (call.method === 'getCamera' || call.method === 'getZoomRange' ||
      call.method === 'getMapApprovalNumbers' || call.method === 'moveCamera') {
      if (this.disposed) { result.error('map_disposed', null, null); return; }
      const map = this.map;
      if (!map || this.status === 'failed') { result.error('map_not_ready', null, null); return; }
      try {
        if (call.method === 'getCamera') {
          const position = map.getCameraPosition();
          if (!position) { result.error('map_not_ready', null, null); return; }
          result.success(this.cameraData(position));
        } else if (call.method === 'getZoomRange') {
          result.success(new Map<string, Any>([
            ['minZoom', map.getMinZoomLevel()], ['maxZoom', map.getMaxZoomLevel()]
          ]));
        } else if (call.method === 'getMapApprovalNumbers') {
          result.success(new Map<string, Any>([
            ['mapContent', map.getMapContentApprovalNumber() ?? ''],
            ['satelliteImage', map.getSatelliteImageApprovalNumber() ?? '']
          ]));
        } else {
          const lat = call.argument('latitude') as number;
          const lng = call.argument('longitude') as number;
          const zoom = call.argument('zoom') as number;
          const animated: boolean = call.argument('animated') as boolean;
          if (!Number.isFinite(lat) || Math.abs(lat) > 90 || !Number.isFinite(lng) || Math.abs(lng) > 180 ||
            !Number.isFinite(zoom) || zoom < 3 || zoom > 20 || Math.fround(zoom) < Math.fround(map.getMinZoomLevel()) ||
            Math.fround(zoom) > Math.fround(map.getMaxZoomLevel()) || typeof animated !== 'boolean') {
            result.error('invalid_argument', null, null); return;
          }
          const rawAnchor: Map<string, Any> | null | undefined =
            call.argument('targetScreenPoint') as Map<string, Any> | null | undefined;
          const layout = this.layout as Record<string, Any>;
          const width: number = layout['width'] as number;
          const height: number = layout['height'] as number;
          if ((rawAnchor != null || this.screenAnchorMode !== ScreenAnchorMode.sdkDefault) &&
              (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0)) {
            result.error('map_not_ready', null, null); return;
          }
          let anchorX: number = width / 2;
          let anchorY: number = height / 2;
          if (rawAnchor != null) {
            if (!(rawAnchor instanceof Map)) {
              result.error('invalid_argument', null, null); return;
            }
            anchorX = rawAnchor.get('x') as number;
            anchorY = rawAnchor.get('y') as number;
            if (!Number.isFinite(anchorX) || !Number.isFinite(anchorY) || anchorX < 0 || anchorX >= width ||
                anchorY < 0 || anchorY >= height) {
              result.error('invalid_argument', null, null); return;
            }
          }
          const update = CameraUpdateFactory.newLatLngZoom(new LatLng(lat, lng), zoom);
          this.cameraEvidence("program");
          if (rawAnchor != null) {
            map.setPointToCenter(
              Math.min(Math.round(vp2px(anchorX)), Math.ceil(vp2px(width)) - 1),
              Math.min(Math.round(vp2px(anchorY)), Math.ceil(vp2px(height)) - 1),
            );
            this.screenAnchorMode = ScreenAnchorMode.custom;
          } else if (this.screenAnchorMode !== ScreenAnchorMode.sdkDefault) {
            this.restoreScreenCenter(map, vp2px(width), vp2px(height));
          }
          if (animated) map.animateCamera(update); else map.moveCamera(update);
          result.success(null);
        }
      } catch (_) { result.error('native_error', null, null); }
    }
    else if (call.method === 'getStatus') result.success(this.status);
    else if (call.method === 'setActive') {
      this.active = call.args === true;
      if (this.active && this.visible) this.nativeView?.onResume(); else this.nativeView?.onPause();
      result.success(null);
    }
    else if (call.method === 'dispose') { this.requestDisposal(); result.success(null); }
    else result.notImplemented();
  }
  private setOptions(map: AMap, args: Map<string, Any>): void {
    if (!(args instanceof Map)) throw new Error('invalid_argument');
    const type: string = args.get('mapType') as string;
    if (type !== 'standard' && type !== 'satellite') throw new Error('invalid_argument');
    const scroll = this.optionFlag(args, 'scrollEnabled');
    const zoom = this.optionFlag(args, 'zoomEnabled');
    const rotate = this.optionFlag(args, 'rotateEnabled');
    const tilt = this.optionFlag(args, 'tiltEnabled');
    const inertia = this.optionFlag(args, 'inertiaEnabled');
    const compass = this.optionFlag(args, 'compassEnabled');
    const scale = this.optionFlag(args, 'scaleEnabled');
    const zoomControls = this.optionFlag(args, 'zoomControlsEnabled');
    const buildings = args.has('buildingsEnabled') ? this.optionFlag(args, 'buildingsEnabled') : true;
    const min: number = args.has('minZoom') ? args.get('minZoom') as number : 3;
    const max: number = args.has('maxZoom') ? args.get('maxZoom') as number : 20;
    if (!Number.isFinite(min) || !Number.isFinite(max) || min < 3 || max > 20 || min > max) {
      throw new Error('invalid_argument');
    }
    const ui = map.getUiSettings();
    if (!ui) throw new Error('native_error');
    const mapType = type === 'satellite' ? MapType.MAP_TYPE_SATELLITE : MapType.MAP_TYPE_NORMAL;
    const oldType = map.getMapType();
    const oldMin = map.getMinZoomLevel();
    const oldMax = map.getMaxZoomLevel();
    this.cameraEvidence('reset');
    if (oldType !== mapType) map.setMapType(mapType);
    this.writeZoomRange(map, min, max);
    const actualMin = map.getMinZoomLevel();
    const actualMax = map.getMaxZoomLevel();
    if (!(Math.fround(actualMin) >= Math.fround(min) && Math.fround(actualMax) <= Math.fround(max) &&
        actualMin <= actualMax)) {
      if (oldType !== mapType) map.setMapType(oldType);
      this.writeZoomRange(map, oldMin, oldMax);
      throw new Error('unsupported_option');
    }
    ui.setScrollGesturesEnabled(scroll && inertia);
    ui.setZoomGesturesEnabled(zoom);
    ui.setRotateGesturesEnabled(rotate);
    ui.setTiltGesturesEnabled(tilt);
    ui.setCompassEnabled(compass);
    ui.setScaleControlsEnabled(scale);
    ui.setZoomControlsEnabled(zoomControls);
    this.trackingDrag = false;
    this.directDragEnabled = scroll && !inertia;
    map.showBuildings(buildings);
    const current = map.getCameraPosition();
    if (current && (current.zoom < actualMin || current.zoom > actualMax)) {
      this.cameraEvidence('program');
      map.moveCamera(CameraUpdateFactory.zoomTo(Math.max(actualMin, Math.min(current.zoom, actualMax))));
    }
  }

  private writeZoomRange(map: AMap, min: number, max: number): void {
    if (min < map.getMinZoomLevel()) map.setMinZoomLevel(min);
    if (max !== map.getMaxZoomLevel()) map.setMaxZoomLevel(max);
    if (min !== map.getMinZoomLevel()) map.setMinZoomLevel(min);
  }

  private optionFlag(args: Map<string, Any>, key: string): boolean {
    const flag: boolean = args.get(key) as boolean;
    if (typeof flag !== 'boolean') throw new Error('invalid_argument');
    return flag;
  }

  private handleCameraTouch(map: AMap, event: TouchEvent): void {
    if (event.type === TouchType.Cancel || event.type === TouchType.Up) {
      this.trackingDrag = false;
      this.cameraEvidence(event.type === TouchType.Cancel ? 'cancel' : 'end');
      return;
    }
    if (event.touches.length > 1) {
      this.trackingDrag = false;
      this.cameraEvidence('multi');
      return;
    }
    if (event.touches.length !== 1) return;
    const touch = event.touches[0];
    if (event.type === TouchType.Down) {
      this.dragX = touch.x;
      this.dragY = touch.y;
      this.trackingDrag = true;
      this.dragging = false;
      const start = map.getCameraPosition();
      if (start) this.cameraEvidence('start', start);
    } else if (event.type === TouchType.Move && this.trackingDrag) {
      const dx = touch.x - this.dragX;
      const dy = touch.y - this.dragY;
      if (!this.dragging && dx * dx + dy * dy < 64) return;
      if (!this.dragging) this.cameraEvidence('drag');
      this.dragging = true;
      this.dragX = touch.x;
      this.dragY = touch.y;
      if (this.directDragEnabled && (dx !== 0 || dy !== 0)) {
        map.moveCamera(CameraUpdateFactory.scrollBy(-vp2px(dx), -vp2px(dy)));
      }
    }
  }

  private fitBounds(map: AMap, args: Map<string, Any>, width: number, height: number): void {
    if (!(args instanceof Map)) throw new Error('invalid_argument');
    const south: number = args.get('south') as number;
    const north: number = args.get('north') as number;
    const west: number = args.get('west') as number;
    const east: number = args.get('east') as number;
    const left: number = args.get('left') as number;
    const right: number = args.get('right') as number;
    const top: number = args.get('top') as number;
    const bottom: number = args.get('bottom') as number;
    const animated: boolean = args.get('animated') as boolean;
    if (!Number.isFinite(south) || !Number.isFinite(north) || south < -85.05112878 ||
        north > 85.05112878 || south >= north || !Number.isFinite(west) ||
        !Number.isFinite(east) || west < -180 || east > 180 || west >= east || east - west > 180 ||
        !Number.isFinite(left) || !Number.isFinite(right) || !Number.isFinite(top) ||
        !Number.isFinite(bottom) || left < 0 || right < 0 || top < 0 || bottom < 0 ||
        typeof animated !== 'boolean') throw new Error('invalid_argument');
    const leftPx = Math.ceil(vp2px(left));
    const rightPx = Math.ceil(vp2px(right));
    const topPx = Math.ceil(vp2px(top));
    const bottomPx = Math.ceil(vp2px(bottom));
    if (leftPx + rightPx >= width || topPx + bottomPx >= height) throw new Error('invalid_argument');
    const bounds = new LatLngBounds(new LatLng(south, west), new LatLng(north, east));
    const update = CameraUpdateFactory.newLatLngBoundsRect(bounds, leftPx, rightPx, topPx, bottomPx);
    this.cameraEvidence("program");
    this.restoreScreenCenter(map, width, height);
    if (animated) map.animateCamera(update); else map.moveCamera(update);
  }

  private restoreScreenCenter(map: AMap, width: number, height: number): void {
    if (this.screenAnchorMode === ScreenAnchorMode.sdkDefault) return;
    map.setPointToCenter(Math.floor(width / 2), Math.floor(height / 2));
    this.screenAnchorMode = ScreenAnchorMode.centered;
  }

  onMapAreaChanged(width: number, height: number): void {
    const map = this.map;
    if (!this.disposed && map && this.screenAnchorMode === ScreenAnchorMode.centered &&
        Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0) {
      this.restoreScreenCenter(map, vp2px(width), vp2px(height));
    }
  }

  private updatePolylines(map: AMap, batch: Map<string, Any>): void {
    const upsert: Array<Map<string, Any>> = batch.get('upsert') as Array<Map<string, Any>>;
    const remove: string[] = batch.get('remove') as string[];
    if (!Array.isArray(upsert) || !Array.isArray(remove) ||
        remove.some((id: string) => typeof id !== 'string')) throw new Error('invalid_argument');
    const options = new Map<string, PolylineOptions>();
    upsert.forEach((item: Map<string, Any>) => {
      if (!(item instanceof Map)) throw new Error('invalid_argument');
      const id: string = item.get('id') as string;
      const width: number = item.get('width') as number;
      const color: number = item.get('color') as number;
      const points: number[][] = item.get('points') as number[][];
      if (typeof id !== 'string' || !id || options.has(id) || remove.includes(id) ||
          !Number.isFinite(width) || width < 1 || width > 128 || !Number.isInteger(color) ||
          color < -2147483648 || color > 2147483647 || !Array.isArray(points) || points.length < 2) {
        throw new Error('invalid_argument');
      }
      options.set(id, new PolylineOptions().addAll(this.decodePoints(points)).setWidth(vp2px(width)).setColor(color));
    });
    const staged = new Map<string, Polyline>();
    try {
      options.forEach((option: PolylineOptions, id: string) => {
        const line = map.addPolyline(option);
        if (!line) throw new Error('native_error');
        staged.set(id, line);
      });
    } catch (_) {
      staged.forEach((line: Polyline) => line.remove());
      throw new Error('native_error');
    }
    staged.forEach((line: Polyline, id: string) => {
      this.polylines.get(id)?.remove();
      this.polylines.set(id, line);
    });
    for (const id of remove) {
      this.polylines.get(id)?.remove();
      this.polylines.delete(id);
    }
  }

  private decodePoints(points: number[][]): ArrayList<LatLng> {
    const coordinates = new ArrayList<LatLng>();
    for (const point of points) {
      if (!Array.isArray(point) || point.length !== 2 ||
          !Number.isFinite(point[0]) || Math.abs(point[0]) > 90 ||
          !Number.isFinite(point[1]) || Math.abs(point[1]) > 180) throw new Error('invalid_argument');
      coordinates.add(new LatLng(point[0], point[1]));
    }
    return coordinates;
  }

  private updatePolygons(map: AMap, batch: Map<string, Any>): void {
    const upsert: Array<Map<string, Any>> = batch.get('upsert') as Array<Map<string, Any>>;
    const remove: string[] = batch.get('remove') as string[];
    if (!Array.isArray(upsert) || !Array.isArray(remove) ||
        remove.some((id: string) => typeof id !== 'string')) throw new Error('invalid_argument');
    const options = new Map<string, PolygonOptions>();
    upsert.forEach((item: Map<string, Any>) => {
      if (!(item instanceof Map)) throw new Error('invalid_argument');
      const id: string = item.get('id') as string;
      const points: number[][] = item.get('points') as number[][];
      const width: number = item.get('strokeWidth') as number;
      const fill: number = item.get('fillColor') as number;
      const stroke: number = item.get('strokeColor') as number;
      if (typeof id !== 'string' || !id || options.has(id) || remove.includes(id) ||
          !Array.isArray(points) || !Number.isFinite(width) || width < 1 || width > 128 ||
          !Number.isInteger(fill) || fill < -2147483648 || fill > 2147483647 ||
          !Number.isInteger(stroke) || stroke < -2147483648 || stroke > 2147483647) throw new Error('invalid_argument');
      const coordinates = this.decodePoints(points);
      if (new Set<string>(points.map((p: number[]) => p.join(','))).size < 3) throw new Error('invalid_argument');
      const option = new PolygonOptions().setFillColor(fill >>> 0).setStrokeColor(stroke >>> 0).setStrokeWidth(vp2px(width));
      option.setPoints(coordinates);
      options.set(id, option);
    });
    options.forEach((option: PolygonOptions, id: string) => {
      const existing = this.polygons.get(id);
      if (existing) {
        existing.setPoints(option.getPoints());
        existing.setFillColor(option.getFillColor());
        existing.setStrokeColor(option.getStrokeColor());
        existing.setStrokeWidth(option.getStrokeWidth());
      } else {
        const polygon = map.addPolygon(option);
        if (!polygon) throw new Error('native_error');
        this.polygons.set(id, polygon);
      }
    });
    for (const id of remove) {
      this.polygons.get(id)?.remove();
      this.polygons.delete(id);
    }
  }

  private updateCircles(map: AMap, batch: Map<string, Any>): void {
    const upsert: Array<Map<string, Any>> = batch.get('upsert') as Array<Map<string, Any>>;
    const remove: string[] = batch.get('remove') as string[];
    if (!Array.isArray(upsert) || !Array.isArray(remove) ||
        remove.some((id: string) => typeof id !== 'string')) throw new Error('invalid_argument');
    const options = new Map<string, CircleOptions>();
    upsert.forEach((item: Map<string, Any>) => {
      if (!(item instanceof Map)) throw new Error('invalid_argument');
      const id: string = item.get('id') as string;
      const latitude: number = item.get('latitude') as number;
      const longitude: number = item.get('longitude') as number;
      const radius: number = item.get('radiusMeters') as number;
      const width: number = item.get('strokeWidth') as number;
      const fill: number = item.get('fillColor') as number;
      const stroke: number = item.get('strokeColor') as number;
      if (typeof id !== 'string' || !id || options.has(id) || remove.includes(id) ||
          !Number.isFinite(latitude) || Math.abs(latitude) > 90 ||
          !Number.isFinite(longitude) || Math.abs(longitude) > 180 ||
          !Number.isFinite(radius) || radius <= 0 || !Number.isFinite(width) ||
          width < 1 || width > 128 ||
          !Number.isInteger(fill) || fill < -2147483648 || fill > 2147483647 ||
          !Number.isInteger(stroke) || stroke < -2147483648 || stroke > 2147483647) {
        throw new Error('invalid_argument');
      }
      options.set(id, new CircleOptions().setCenter(new LatLng(latitude, longitude)).setRadius(radius)
        .setFillColor(fill >>> 0).setStrokeColor(stroke >>> 0).setStrokeWidth(vp2px(width)));
    });
    const staged = new Map<string, Circle>();
    try {
      options.forEach((option: CircleOptions, id: string) => {
        const circle = map.addCircle(option);
        if (!circle) throw new Error('native_error');
        staged.set(id, circle);
      });
    } catch (_) {
      staged.forEach((circle: Circle) => circle.remove());
      throw new Error('native_error');
    }
    staged.forEach((circle: Circle, id: string) => {
      this.circles.get(id)?.remove();
      this.circles.set(id, circle);
    });
    for (const id of remove) {
      this.circles.get(id)?.remove();
      this.circles.delete(id);
    }
  }

  private cameraData(position: CameraPosition): Map<string, Any> {
    return new Map<string, Any>([['latitude', position.target.latitude],
      ['longitude', position.target.longitude], ['zoom', position.zoom], ['bearing', position.bearing], ['tilt', position.tilt]]);
  }
  private cameraEvidence(kind: string, position?: CameraPosition): void {
    const data: Map<string, Any> = position ? this.cameraData(position) : new Map<string, Any>();
    data.set('kind', kind);
    this.channel.invokeMethod('cameraEvidence', data);
  }
  private cameraEvent(method: string, position: CameraPosition): void {
    if (!this.disposed) this.channel.invokeMethod(method, this.cameraData(position));
  }
  private update(value: string): void {
    if (this.disposed || (this.status === 'loaded' && value !== 'failed')) return;
    this.status = value;
    this.channel.invokeMethod('status', value);
  }
  onFlutterViewAttached(root: DVModel): void {
    if (this.disposed) return;
    // This runtime appends the newly created instance immediately before this callback.
    // Retain its identity: reattachment must never select another map's last node.
    const model = this.displayModel ?? root.children[root.children.length - 1];
    if (!model || !root.children.includes(model)) { this.update('failed'); return; }
    const params = model.params as Record<string, Any>;
    this.layout = model.params;
    const controller = params['nodeController'] as EmbeddingNodeController;
    if (!(controller instanceof EmbeddingNodeController)) { this.update('failed'); return; }
    this.displayModel = model;
    controller.setRenderOption(this, '', NodeRenderType.RENDER_TYPE_DISPLAY, Direction.Ltr);
    controller.rebuild();
  }
  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(buildMap); }
  onActive(): void { this.visible = true; if (!this.disposed && this.active) this.nativeView?.onResume(); }
  onInactive(): void { this.visible = false; if (!this.disposed) this.nativeView?.onPause(); }
  requestDisposal(): void {
    if (this.disposed) return;
    this.disposed = true;
    try {
      if (this.registered) {
        MapViewManager.getInstance().unregisterMapViewCreatedCallback(this.createdCallback);
        this.registered = false;
      }
    } finally {
      this.channel.setMethodCallHandler(null);
    }
  }
  dispose(): void {
    if (this.released) return;
    this.released = true;
    // Only the platform-view lifecycle destroys the SDK, after node disposal.
    // The earlier Dart channel request only invalidates callbacks.
    try {
      this.requestDisposal();
      this.nativeView?.onPause();
      this.markers.clear();
      this.polylines.forEach((line: Polyline) => line.remove());
      this.polylines.clear();
      this.polygons.forEach((polygon: Polygon) => polygon.remove());
      this.polygons.clear();
      this.circles.forEach((circle: Circle) => circle.remove());
      this.circles.clear();
      this.nativeView?.onDestroy();
    } finally {
      this.map = null;
      this.nativeView = null;
      this.displayModel = null;
      this.onDisposed();
    }
  }
}

@Component
struct DisplayMapComponent {
  name: string = '';
  view?: AMapNativeView;
  @ObjectLink layout: DVModelParameters;

  build() {
    MapViewComponent({ mapViewName: this.name })
      .width((this.layout as Record<string, Any>)['width'] as number)
      .height((this.layout as Record<string, Any>)['height'] as number)
      .onAreaChange((previous: Area, current: Area) => {
        if (previous.width !== current.width || previous.height !== current.height) {
          this.view?.onMapAreaChanged(Number(current.width), Number(current.height));
        }
      })
  }
}

@Builder
function buildMap(params: Params) {
  if ((params.platformView as AMapNativeView).valid) {
    DisplayMapComponent({ name: (params.platformView as AMapNativeView).name,
      layout: (params.platformView as AMapNativeView).layout, view: params.platformView as AMapNativeView })
  } else {
    Text('Map initialization required')
  }
}
