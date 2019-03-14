
type key = string | number;

type seconds = number;

type color = string;

type MapString<T> = { [key: string]: T };
type MapNumber<T> = { [key: number]: T };

type int = number;
type MapInt<T> = MapNumber<T>;


/////////////////////////////////////////////////////////////////////
// JQUERY EXTENSIONS

// tslint:disable-next-line: interface-name
interface JQuery {
    enable(x: boolean): JQuery;
}

jQuery.fn.enable = function(x: boolean) {
    // Set the values to enabled/disabled
    return this.each(function() {
        if (x)
            $(this).removeAttr("disabled");
        else
            $(this).attr("disabled", "disabled");
    });
};


/////////////////////////////////////////////////////////////////////
// BROWSER HELPER METHODS

// Given "?foo=bar&baz=1" returns {foo:"bar",baz:"1"}
function uriQueryParameters(s: string): MapString<string> {
    // From https://stackoverflow.com/questions/901115/get-querystring-values-with-jquery/3867610#3867610
    const params: MapString<string> = {};
    const a = /\+/g;  // Regex for replacing addition symbol with a space
    const r = /([^&=]+)=?([^&]*)/g;
    const d = (x: string) => decodeURIComponent(x.replace(a, " "));
    const q = s.substring(1);

    while (true) {
        const e = r.exec(q);
        if (!e) break;
        params[d(e[1])] = d(e[2]);
    }
    return params;
}


/////////////////////////////////////////////////////////////////////
// STRING FORMATTING

function showTime(x: seconds): string {
    function digits(x: seconds) {const s = String(x); return s.length === 1 ? "0" + s : s; }

    if (x >= 3600) {
        x = Math.round(x / 60);
        return Math.floor(x / 60) + "h" + digits(x % 60) + "m";
    } else if (x >= 60) {
        x = Math.round(x);
        return Math.floor(x / 60) + "m" + digits(x % 60) + "s";
    } else
        return x.toFixed(2) + "s";
}

function showPerc(x: number): string {
    return (x * 100).toFixed(2) + "%";
}

function showInt(x: int): string {
    // From https://stackoverflow.com/questions/2901102/how-to-print-a-number-with-commas-as-thousands-separators-in-javascript
    // Show, with commas
    return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function plural(n: int, not1 = "s", is1 = ""): string {
    return n === 1 ? is1 : not1;
}


/////////////////////////////////////////////////////////////////////
// MISC

function compareFst<A>(a: [number, A], b: [number, A]): number {
    return a[0] - b[0];
}

function compareSnd<A>(a: [A, number], b: [A, number]): number {
    return a[1] - b[1];
}

function sortOn<A>(xs: A[], f: (x: A) => number): A[] {
    return xs.map(x => pair(f(x), x)).sort(compareFst).map(snd);
}

function last<A>(xs: A[]): A {
    return xs[xs.length - 1];
}

function maximum<A>(xs: A[], start: A): A {
    let res: A = start;
    for (const x of xs)
        if (x > res)
            res = x;
    return res;
}

function minimum<A>(xs: A[], start?: A): A {
    let res: A = start;
    for (const x of xs)
        if (res === undefined || x < res)
            res = x;
    return res;
}

function pair<A, B>(a: A, b: B): [A, B] {
    return [a, b];
}

function fst<A, B>([x, _]: [A, B]): A {
    return x;
}

function snd<A, B>([_, x]: [A, B]): B {
    return x;
}

function execRegExp(r: string | RegExp, s: string): string[] {
    if (typeof r === "string")
        return s.indexOf(r) === -1 ? null : [];
    else
        return r.exec(s);
}

function cache<K, V>(key: (k: K) => string, op: (k: K) => V): (k: K) => V {
    const store: MapString<V> = {};
    return k => {
        const s = key(k);
        if (!(s in store))
            store[s] = op(k);
        return store[s];
    };
}

function lazy<V>(thunk: () => V): () => V {
    let store: V = null;
    let done = false;
    return () => {
        if (!done) {
            store = thunk();
            done = true;
        }
        return store;
    };
}

interface Array<T> {
    insertSorted(x: T, compare: (a: T, b: T) => number): T[];
    concatLength<A, T extends A[]>(): int;
    sum<T extends number>(): number;
}

Array.prototype.sum = function<T>(): number {
    let res = 0;
    for (const x of this as number[])
        res += x;
    return res;
};


Array.prototype.insertSorted = function<T>(x: T, compare: (a: T, b: T) => number): T[] {
    const xs = this as T[];
    let start = 0;
    let stop = xs.length - 1;
    let middle = 0;
    while (start <= stop) {
        middle = Math.floor((start + stop) / 2);
        if (compare(xs[middle], x) > 0)
            stop = middle - 1;
        else
            start = middle + 1;
    }
    xs.splice(start, 0, x);
    return xs;
};

Array.prototype.concatLength = function<A>(): int {
    let res = 0;
    for (const x of this as A[][])
        res += x.length;
    return res;
};


// Use JSX with el instead of React.createElement
// Originally from https://gist.github.com/sergiodxa/a493c98b7884128081bb9a281952ef33

// our element factory
function createElement(type: string, props?: MapString<any>, ...children: any[]) {
    const element = document.createElement(type);

    for (const name in props || {}) {
        if (name.substr(0, 2) === "on")
            element.addEventListener(name.substr(2), props[name]);
        else
            element.setAttribute(name, props[name]);
    }
    for (const child of children.flat(10)) {
        const c = typeof child === "object" ? child : document.createTextNode(child.toString());
        element.appendChild(c);
    }
    return element;
}

// How .tsx gets desugared
const React = {createElement};
