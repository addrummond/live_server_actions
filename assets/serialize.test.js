import { beforeEach, describe, expect, test, vi } from "vitest";
import { deserializeSpecials, getSerializationSpecials } from "./serialize";

describe("getSerializationSpecials", () => {
  test("should return null for a complex value with no special objects", () => {
    const data = {foo: 1, bar: 2, amp: [[[1,2,{foo: 19}]]]};
    const specials = getSerializationSpecials(data, null);
    expect(specials).toBeNull();
  });

  test("should serialize a Date object", () => {
    const date = new Date();
    const specials = getSerializationSpecials(date, null);
    expect(specials).toEqual({ type: 'Date' });
  });

  test("should serialize a Date object nested in an array", () => {
    const specials = getSerializationSpecials([1, new Date(), 2], null);
    expect(specials).toEqual({ type: 'id', subs: [{ path: 1, type: 'Date' }] });
  });

  test("should serialize a Date object nested in an object", () => {
    const specials = getSerializationSpecials({foo: 1, bar: new Date()}, null);
    expect(specials).toEqual({ type: 'id', subs: [{ path: "bar", type: 'Date' }] });
  });

  test("should serialize deeply nested Date objects", () => {
    const thedate = new Date();
    const specials = getSerializationSpecials(
      [
        {foo: 1, bar: [5, new Date()]},
        {baz: [2, {qux: new Date(), fuzz: new Map([["date", thedate]])}]}
      ],
      null
    );
    expect(specials).toEqual(
      {
        subs: [
          {
            path: 0,
            subs: [
              {
                path: "bar",
                subs: [
                  {
                    path: 1,
                    type: "Date",
                  },
                ],
                type: "id",
              },
            ],
            type: "id",
          },
          {
            path: 1,
            subs: [
              {
                path: "baz",
                subs: [
                  {
                    path: 1,
                    subs: [
                      {
                        path: "qux",
                        type: "Date",
                      },
                      {
                        path: "fuzz",
                        shadow: {
                          date: thedate,
                        },
                        subs: [
                          {
                            path: "date",
                            type: "Date",
                          },
                        ],
                        type: "shadow_id",
                      },
                    ],
                    type: "id",
                  },
                ],
                type: "id",
              },
            ],
            type: "id",
          },
        ],
        type: "id",
      }
    );
  });

  test("should do nothing for a deeply nested value with no Date objects", () => {
    const specials = getSerializationSpecials(
      [
        {foo: 1, bar: [5, "notadate"]},
        {baz: [2, {qux: "notadate"}]}
      ],
      null
    );
    expect(specials).toBeNull()
  });

  test("should serialize objects with null prototypes correctly", () => {
    const data = Object.create(null, {
      foo: { value: 1, enumerable: true },
      bar: { value: new Date(), enumerable: true },
      nonenum: { value: new Date(), enumerable: false }
    });
    const specials = getSerializationSpecials(data, null);
    expect(specials).toEqual({ type: 'id', subs: [{ path: "bar", type: 'Date' }] });
  })

  test("should serialize elements of sets and maps correctly", () => {
    const data = {
      foo: new Map([
        ["mykey1", [1, new Set([4, 5, 6])]],
        [999, new Map([[1,2], [3,4]])]
      ])
    }

    const specials = getSerializationSpecials(data, null);
    expect(specials).toEqual(
      {
        subs: [
          {
            path: "foo",
            shadow: {
              "999": new Map([
                [1, 2],
                [3, 4],
              ]),
              mykey1: [
                1,
                new Set([
                  4,
                  5,
                  6,
                ]),
              ],
            },
            subs: [
              {
                path: "mykey1",
                subs: [
                  {
                    path: 1,
                    shadow: [
                      4,
                      5,
                      6,
                    ],
                    type: "Set",
                  },
                ],
                type: "id",
              },
              {
                path: 999,
                shadow: {
                  "1": 2,
                  "3": 4,
                },
                type: "shadow_id",
              },
            ],
            type: "shadow_id",
          },
        ],
        type: "id",
      }
    );
  });
});

describe("deserializeSpecials", () => {
  const consoleWarnMock = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

  beforeEach(() => {
    consoleWarnMock.mockReset();
  })

  test("should work with undefined specials", () => {
    const data = {foo: 1, bar: 2};
    const specials = undefined;
    const result = deserializeSpecials(data, specials);
    expect(result).toEqual(data);
  })

  test("should work with null specials", () => {
    const data = {foo: 1, bar: 2};
    const specials = null;
    const result = deserializeSpecials(data, specials);
    expect(result).toEqual(data);
  })

  test("should deserialize a Date object", () => {
    const date = '2025-03-29T11:53:52.177Z';
    const specials = { type: 'Date' };
    const result = deserializeSpecials(date, specials);
    expect(result).toEqual(new Date(date));
  });

  test("should deserialize a Date object nested in an array", () => {
    const date = '2025-03-29T11:53:52.177Z';
    const specials = {type: 'id', subs: [{ path: 1, type: 'Date' }]};
    const result = deserializeSpecials([1, date, 2], specials);
    expect(result[1]).toEqual(new Date(date));
  });

  test("should deserialize a Date object nested in an object", () => {
    const date = '2025-03-29T11:53:52.177Z'
    const specials = {type: 'id', subs: [{ path: 'bar', type: 'Date' }]};
    const result = deserializeSpecials({foo: 1, bar: date}, specials);
    expect(result.bar).toEqual(new Date(date));
  });

  test("should deserialize multiple Date objects in a complex value", () => {
    const date1 = '2025-03-29T11:53:52.177Z';
    const date2 = '2025-03-29T12:04:53.267Z';
    const specials = {type: 'id', subs: [{ path: 'bar', type: 'Date' }, { path: 'amp', type: 'id', subs: [{ path: 1, type: 'Date' }] }]};
    const result = deserializeSpecials({foo: 1, bar: date1, amp: [1, date2, 3]}, specials);
    expect(result.bar).toEqual(new Date(date1));
    expect(result.amp[1]).toEqual(new Date(date2));
  });

  test("ignores nonexistent paths, processes other valid paths, and logs warning", () => {
    const date1 = '2025-03-29T11:53:52.177Z';
    const date2 = '2025-03-29T12:04:53.267Z';
    const specials = {type: 'id', subs: [{ path: 'bar', type: 'Date' }, { path: 'amp', type: 'id', subs: [{ path: 1, type: 'Date' }, { path: 999, type: 'Date' }] }]};
    const result = deserializeSpecials({foo: 1, bar: date1, amp: [1, date2, 3]}, specials);
    expect(result.bar).toEqual(new Date(date1));
    expect(result.amp[1]).toEqual(new Date(date2));
    expect(consoleWarnMock).toHaveBeenCalledExactlyOnceWith('Path 999 not found in value when deserializing specials');
  });

  test("ignores unrecognized serialization types, processes other valid deserializations, and logs warning", () => {
    const date1 = '2025-03-29T11:53:52.177Z';
    const date2 = '2025-03-29T12:04:53.267Z';
    const specials = {type: 'id', subs: [{ path: 'bar', type: 'Date' }, { path: 'amp', type: 'id', subs: [{ path: 1, type: 'invalid' }] }]};
    const result = deserializeSpecials({foo: 1, bar: date1, amp: [1, date2, 3]}, specials);
    expect(result.bar).toEqual(new Date(date1));
    expect(result.amp[1]).toEqual(date2);
    expect(consoleWarnMock).toHaveBeenCalledExactlyOnceWith('Unknown special type invalid');
  });
})
