import { beforeEach, describe, expect, test, vi } from "vitest";
import { deserializeSpecials, getSerializationSpecials } from "./serialize";

describe("getSerializationSpecials", () => {
  test("should serialize a Date object", () => {
    const date = new Date();
    const specials = getSerializationSpecials(date);
    expect(specials).toEqual([{ path: [], type: 'Date' }]);
  });

  test("should serialize a Date object nested in an array", () => {
    const specials = getSerializationSpecials([1, new Date(), 2]);
    expect(specials).toEqual([{ path: [1], type: 'Date' }]);
  });

  test("should serialize a Date object nested in an object", () => {
    const specials = getSerializationSpecials({foo: 1, bar: new Date()});
    expect(specials).toEqual([{ path: ["bar"], type: 'Date' }]);
  });

  test("should serialize deeply nested Date objects", () => {
    const specials = getSerializationSpecials(
      [
        {foo: 1, bar: [5, new Date()]},
        {baz: [2, {qux: new Date()}]}
      ]
    );
    expect(specials).toEqual([
      { path: [1, "baz", 1, "qux"], type: 'Date' },
      { path: [0, "bar", 1], type: 'Date' }
    ]);
  });

  test("should do nothing for a deeply nested value with no Date objects", () => {
    const specials = getSerializationSpecials(
      [
        {foo: 1, bar: [5, "notadate"]},
        {baz: [2, {qux: "notadate"}]}
      ]
    );
    expect(specials).toEqual([]);
  });

  test("should serialize elements of sets and maps in the correct order", () => {
    const data = {
      foo: new Map([
        ["mykey1", [1, new Set([4, 5, 6])]],
        [999, new Map([[1,2], [3,4]])]
      ])
    }

    const specials = getSerializationSpecials(data);
    console.log(specials);
    expect(specials).toEqual(
      [
        {
          path: [ 'foo' ],
          type: 'shadow_id',
          shadow: { '999': new Map([[1,2], [3,4]]), mykey1: [1, new Set([4, 5, 6])] }
        },
        {
          path: [ 'foo', 999 ],
          type: 'shadow_id',
          shadow: { '1': 2, '3': 4 }
        },
        { path: [ 'foo', 'mykey1', 1 ], type: 'Set', shadow: [ 4, 5, 6 ] }
      ]
    );
  });
});

describe("deserializeSpecials", () => {
  const consoleWarnMock = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

  beforeEach(() => {
    consoleWarnMock.mockReset();
  })  

  test("should deserialize a Date object", () => {
    const date = '2025-03-29T11:53:52.177Z';
    const specials = [{ path: [], type: 'Date' }];
    const result = deserializeSpecials(date, specials);
    expect(result).toEqual(new Date(date));
  });

  test("should deserialize a Date object nested in an array", () => {
    const date = '2025-03-29T11:53:52.177Z';
    const specials = [{ path: [1], type: 'Date' }];
    const result = deserializeSpecials([1, date, 2], specials);
    expect(result[1]).toEqual(new Date(date));
  });

  test("should deserialize a Date object nested in an object", () => {
    const date = '2025-03-29T11:53:52.177Z'
    const specials = [{ path: ["bar"], type: 'Date' }];
    const result = deserializeSpecials({foo: 1, bar: date}, specials);
    expect(result.bar).toEqual(new Date(date));
  });

  test("should deserialize multiple Date objects in a complex value", () => {
    const date1 = '2025-03-29T11:53:52.177Z';
    const date2 = '2025-03-29T12:04:53.267Z';
    const specials = [{ path: ["bar"], type: 'Date' }, { path: ["amp", 1], type: 'Date' }];
    const result = deserializeSpecials({foo: 1, bar: date1, amp: [1, date2, 3]}, specials);
    expect(result.bar).toEqual(new Date(date1));
    expect(result.amp[1]).toEqual(new Date(date2));
  });

  test("ignores nonexistent paths, processes other valid paths, and logs warning", () => {
    const date1 = '2025-03-29T11:53:52.177Z';
    const date2 = '2025-03-29T12:04:53.267Z';
    const specials = [{ path: ["bar"], type: 'Date' }, { path: ["amp", 1], type: 'Date' }, { path: "invalid", type: 'Date' }];
    const result = deserializeSpecials({foo: 1, bar: date1, amp: [1, date2, 3]}, specials);
    expect(result.bar).toEqual(new Date(date1));
    expect(result.amp[1]).toEqual(new Date(date2));
    expect(consoleWarnMock).toHaveBeenCalledExactlyOnceWith('Path "invalid" not found in value when deserializing specials');
  });

  test("ignores unrecognized serialization types, processes other valid deserializations, and logs warning", () => {
    const date1 = '2025-03-29T11:53:52.177Z';
    const date2 = '2025-03-29T12:04:53.267Z';
    const specials = [{ path: ["bar"], type: 'Date' }, { path: ["amp", 1], type: 'invalid' }];
    const result = deserializeSpecials({foo: 1, bar: date1, amp: [1, date2, 3]}, specials);
    expect(result.bar).toEqual(new Date(date1));
    expect(result.amp[1]).toEqual(date2);
    expect(consoleWarnMock).toHaveBeenCalledExactlyOnceWith('Unknown special type invalid');
  });
})
