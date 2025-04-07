import React from "react"
import { serverActions } from "live_server_actions";
import { useState, useActionState, startTransition } from 'react';

export const RandomQuoteChooser = () => {
  const [fruit, setFruit] = useState("Apple");
  const [quote, getQuoteAction, quoteIsLoading] = useActionState(
    () => serverActions.QuotesWeb.QuotesLive.get_quote({ fruit, extra:
      new Map([
        ["mykey1", [1, new Set([4, 5, 6])]],
        [999, new Map([[1,2], [3,4]])]
      ])
    }),
    null
  );
  
  return <div>
    <div className="quote-chooser">
      <p><label htmlFor="fruit">🍎🍍🍐&nbsp;&nbsp;Choose a fruit&nbsp;&nbsp;🍐🍍🍎</label></p>
      <select id="fruit" name="fruit" onChange={e => setFruit(e.target.value)} value={fruit}>
        <option value="Apple">Apple</option>
        <option value="Pineapple">Pineapple</option>
        <option value="Pear">Pear</option>
      </select>
      <p>
        <button
          type="button"
          onClick={() => {
            startTransition(() => {
              getQuoteAction();
            });
          }}
        >
          Load {quote ? "another" : "a"} quote
        </button>
      </p>
    </div>
    {quoteIsLoading ? <div className="lds-ring"><div></div></div> : <Quote quote={quote} />}
  </div>
};

function Quote({ quote }) {
  return quote && <div className="quote">
    <p><i>{quote.quote}</i></p>
    <p>– {quote.author} ({quote.year})</p>
  </div>
}
