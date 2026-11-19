import { common } from '@kit.AbilityKit';
import ArrayList from '@ohos.util.ArrayList';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import { AMapException, GeocodeAddress, GeocodeQuery, GeocodeSearch, Inputtips, InputtipsListener, InputtipsQuery,
  LatLonPoint, ReGeocodeAddress, ReGeocodeQuery, PoiItem, PoiQuery, PoiSearch, PoiSearchBound, ServiceSettings, Tip } from '@amap/amap_lbs_search';
import { Any, MethodCall, MethodResult } from '@ohos/flutter_ohos';

export class AMapSearchBridge {
  private configured: boolean = false;
  private disposed: boolean = false;

  async lookup(context: common.Context, key: string, call: MethodCall, result: MethodResult): Promise<void> {
    const latitude = call.argument('latitude') as number;
    const longitude = call.argument('longitude') as number;
    const radius = call.argument('radiusMeters') as number;
    if (!Number.isFinite(latitude) || Math.abs(latitude) > 90 ||
      !Number.isFinite(longitude) || Math.abs(longitude) > 180 ||
      !Number.isInteger(radius) || radius < 1 || radius > 3000) {
      result.error('invalid_argument', null, null);
      return;
    }

    try {
      this.configure(context, key);
      const query = new ReGeocodeQuery(new LatLonPoint(latitude, longitude), radius, GeocodeSearch.AMAP);
      query.setExtensions(GeocodeSearch.EXTENSIONS_ALL);
      const address = await new GeocodeSearch(context).getFromLocation(query);
      if (this.disposed) return;
      if (address) result.success(this.payload(address));
      else result.error('geocode_no_result', null, null);
    } catch (error) {
      if (this.disposed) return;
      const code = error instanceof AMapException ? error.getErrorCode() : null;
      result.error('geocode_failed', null, code);
    }
  }

  async searchPoi(context: common.Context, key: string, call: MethodCall, result: MethodResult): Promise<void> {
    const keyword = (call.argument('keyword') as string | null)?.trim() ?? '';
    const city = (call.argument('city') as string | null) ?? undefined;
    const category = (call.argument('categoryCode') as string | null) ?? '';
    const pageNumber = (call.argument('page') as number | null) ?? 1;
    const size = (call.argument('pageSize') as number | null) ?? 20;
    const radius = call.argument('radiusMeters') as number | null | undefined;
    const latitude = call.argument('latitude') as number;
    const longitude = call.argument('longitude') as number;
    const validCenter = Number.isFinite(latitude) && Math.abs(latitude) <= 90 &&
      Number.isFinite(longitude) && Math.abs(longitude) <= 180;
    if (!Number.isInteger(pageNumber) || pageNumber < 1 || pageNumber > 100 ||
      !Number.isInteger(size) || size < 1 || size > 25 || (radius == null && !keyword) ||
      (radius != null && (!Number.isInteger(radius) || radius < 1 || radius > 50000 || !validCenter))) {
      result.error('invalid_argument', null, null);
      return;
    }

    try {
      this.configure(context, key);
      const query = new PoiQuery(keyword, category, city);
      query.setCityLimit(!!city);
      query.setPageNum(pageNumber);
      query.setPageSize(size);
      const search = new PoiSearch(context, query);
      if (radius != null) {
        search.setBound(PoiSearchBound.createCircleSearchBound(new LatLonPoint(latitude, longitude), radius, true));
      }
      const page = await search.searchPOI();
      if (this.disposed) return;
      if (!page) {
        result.error('poi_search_failed', null, null);
        return;
      }
      const places: Map<string, Any>[] = [];
      page.getPois()?.forEach((poi: PoiItem) => { places.push(this.poiPayload(poi)); });
      result.success(places);
    } catch (error) {
      if (this.disposed) return;
      const code = error instanceof AMapException ? error.getErrorCode() : null;
      result.error('poi_search_failed', null, code);
    }
  }

  async poiById(context: common.Context, key: string, call: MethodCall, result: MethodResult): Promise<void> {
    const id = (call.argument('id') as string | null)?.trim() ?? '';
    if (!id || id.includes('|')) {
      result.error('invalid_argument', null, null); return;
    }
    try {
      this.configure(context, key);
      const query = new PoiQuery('', '', undefined);
      query.setExtensions(PoiSearch.EXTENSIONS_ALL);
      const poi = await new PoiSearch(context, query).searchPOIId(id);
      if (this.disposed) return;
      const places: Map<string, Any>[] = [];
      if (poi) places.push(this.poiPayload(poi));
      result.success(places);
    } catch (error) {
      if (this.disposed) return;
      result.error('poi_search_failed', null, error instanceof AMapException ? error.getErrorCode() : null);
    }
  }

  async forwardGeocode(context: common.Context, key: string, call: MethodCall, result: MethodResult): Promise<void> {
    const address = (call.argument('address') as string | null)?.trim() ?? '';
    const city = (call.argument('city') as string | null) ?? undefined;
    if (!address) {
      result.error('invalid_argument', null, null); return;
    }
    try {
      this.configure(context, key);
      const matches = await new GeocodeSearch(context).getFromLocationName(new GeocodeQuery(address, city));
      if (this.disposed) return;
      if (!matches) { result.error('geocode_failed', null, null); return; }
      const candidates: Map<string, Any>[] = [];
      matches.forEach((match: GeocodeAddress) => {
        const item: Map<string, Any> = this.point(match.getLatLonPoint());
        item.set('formattedAddress', match.getFormatAddress() ?? null);
        item.set('level', match.getLevel() ?? null);
        item.set('country', match.getCountry() ?? null);
        item.set('province', match.getProvince() ?? null);
        item.set('city', match.getCity() ?? null);
        item.set('district', match.getDistrict() ?? null);
        item.set('adCode', match.getAdCode() ?? null);
        item.set('township', match.getTownship() ?? null);
        item.set('neighborhood', match.getNeighborhood() ?? null);
        item.set('building', match.getBuilding() ?? null);
        candidates.push(item);
      });
      result.success(candidates);
    } catch (error) {
      if (this.disposed) return;
      result.error('geocode_failed', null, error instanceof AMapException ? error.getErrorCode() : null);
    }
  }

  private poiPayload(poi: PoiItem): Map<string, Any> {
    const item: Map<string, Any> = this.point(poi.getLatLonPoint());
    item.set('id', poi.getPoiId() ?? null);
    item.set('name', poi.getTitle() ?? null);
    item.set('address', poi.getSnippet() ?? null);
    item.set('category', poi.getTypeDes() ?? null);
    item.set('categoryCode', poi.getTypeCode() ?? null);
    item.set('province', poi.getProvinceName() ?? null);
    item.set('city', poi.getCityName() ?? null);
    item.set('district', poi.getAdName() ?? null);
    item.set('adCode', poi.getAdCode() ?? null);
    item.set('telephone', poi.getTel() ?? null);
    return item;
  }

  inputTips(context: common.Context, key: string, call: MethodCall, result: MethodResult): void {
    const keyword = (call.argument('keyword') as string | null)?.trim() ?? '';
    const city = (call.argument('city') as string | null) ?? undefined;
    const category = call.argument('categoryCode') as string | null;
    if (!keyword) {
      result.error('invalid_argument', null, null);
      return;
    }
    try {
      this.configure(context, key);
      const query = new InputtipsQuery(keyword, city);
      query.setCityLimit(!!city);
      if (category) query.setType(category);
      const listener: InputtipsListener = {
        onGetInputtips: (tips: ArrayList<Tip>, code: number): void => {
          if (this.disposed) return;
          if (code !== 1000 || !tips) {
            result.error('poi_search_failed', null, code);
            return;
          }
          const suggestions: Map<string, Any>[] = [];
          tips.forEach((tip: Tip) => {
            const item: Map<string, Any> = this.point(tip.getPoint());
            item.set('name', tip.getName() ?? null);
            item.set('id', tip.getPoiID() ?? null);
            item.set('address', tip.getAddress() ?? null);
            item.set('district', tip.getDistrict() ?? null);
            item.set('adCode', tip.getAdcode() ?? null);
            item.set('categoryCode', tip.getTypeCode() ?? null);
            suggestions.push(item);
          });
          result.success(suggestions);
        }
      };
      new Inputtips(context, listener, query).requestInputtipsAsyn();
    } catch (error) {
      const code = error instanceof AMapException ? error.getErrorCode() : null;
      result.error('poi_search_failed', null, code);
    }
  }

  private configure(context: common.Context, key: string): void {
    if (this.configured) return;
    ServiceSettings.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, context);
    ServiceSettings.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, context);
    ServiceSettings.getInstance().setApiKey(key);
    ServiceSettings.getInstance().setProtocol(ServiceSettings.HTTPS);
    this.configured = true;
  }

  dispose(): void {
    this.disposed = true;
  }

  private payload(address: ReGeocodeAddress): Map<string, Any> {
    const pois: Map<string, Any>[] = [];
    address.getPois()?.forEach((poi) => {
      const item: Map<string, Any> = this.point(poi.getLatLonPoint());
      item.set('id', poi.getPoiId() ?? null);
      item.set('name', poi.getTitle() ?? null);
      item.set('type', poi.getTypeDes() ?? null);
      item.set('address', poi.getSnippet() ?? null);
      item.set('distanceMeters', poi.getDistance());
      pois.push(item);
    });
    const aois: Map<string, Any>[] = [];
    address.getAois()?.forEach((aoi) => {
      const item: Map<string, Any> = this.point(aoi.getAoiCenterPoint());
      item.set('id', aoi.getAoiId() ?? null);
      item.set('name', aoi.getAoiName() ?? null);
      item.set('type', aoi.getType() ?? null);
      item.set('adCode', aoi.getAdCode() ?? null);
      item.set('distanceMeters', aoi.getDistance());
      item.set('areaSquareMeters', aoi.getAoiArea());
      aois.push(item);
    });
    const result: Map<string, Any> = new Map<string, Any>();
    result.set('formattedAddress', address.getFormatAddress() ?? null);
    result.set('country', address.getCountry() ?? null);
    result.set('province', address.getProvince() ?? null);
    result.set('city', address.getCity() ?? null);
    result.set('cityCode', address.getCityCode() ?? null);
    result.set('district', address.getDistrict() ?? null);
    result.set('adCode', address.getAdCode() ?? null);
    result.set('township', address.getTownship() ?? null);
    result.set('townCode', address.getTownCode() ?? null);
    result.set('neighborhood', address.getNeighborhood() ?? null);
    result.set('building', address.getBuilding() ?? null);
    result.set('pois', pois);
    result.set('aois', aois);
    return result;
  }

  private point(point: LatLonPoint | undefined): Map<string, Any> {
    const result: Map<string, Any> = new Map<string, Any>();
    if (point) {
      result.set('latitude', point.getLatitude());
      result.set('longitude', point.getLongitude());
    }
    return result;
  }
}
