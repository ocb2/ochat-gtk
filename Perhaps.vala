public interface Perhaps<T> : Object {}
public class Some<T> : Perhaps<T>, Object {
	public T data;
	public Some(T x) { data = x; }
}
public class None<T> : Perhaps<T>, Object {}